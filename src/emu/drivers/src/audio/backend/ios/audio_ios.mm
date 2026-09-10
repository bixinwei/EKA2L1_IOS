/*
 * Copyright (c) 2024 EKA2L1 Team.
 *
 * This file is part of EKA2L1 project.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
#include <drivers/audio/backend/ios/audio_ios.h>
#include <common/log.h>

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#include <atomic>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

namespace eka2l1::drivers {
    static double ensure_audio_session() {
        static bool configured = false;
        if (configured) {
            return [AVAudioSession sharedInstance].sampleRate;
        }
        configured = true;

        NSError *err = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback
                 withOptions:AVAudioSessionCategoryOptionMixWithOthers
                       error:&err];
        if (err) {
            LOG_WARN(DRIVER_AUD, "AVAudioSession setCategory failed: {}", [[err localizedDescription] UTF8String]);
            err = nil;
        }

        // The output route owns its real rate (usually 48 kHz on modern iPhones). The caller
        // reads it after activation and explicitly resamples guest PCM if needed; merely
        // requesting 44.1 kHz and assuming it was accepted can make sound play at the wrong rate.
        [session setPreferredSampleRate:48000.0 error:&err]; err = nil;
        [session setPreferredIOBufferDuration:0.023 error:&err]; err = nil; // ~1024 frames @ 44.1k

        [session setActive:YES error:&err];
        if (err) {
            LOG_WARN(DRIVER_AUD, "AVAudioSession setActive failed: {}", [[err localizedDescription] UTF8String]);
        }
        return session.sampleRate;
    }

    class ios_audio_output_stream : public audio_output_stream {
        AudioComponentInstance unit_;
        data_callback callback_;
        std::uint32_t rate_;           // guest PCM rate requested by the emulator
        std::uint32_t hardware_rate_;  // active output route rate reported by AVAudioSession
        std::uint8_t chans_;

        std::atomic<float> volume_;
        std::atomic<bool> playing_;
        std::atomic<std::uint64_t> source_frames_rendered_;

        // Interleaved guest PCM retained between callbacks for linear rate conversion. AudioUnit
        // asks in hardware-rate frames, while the Symbian player supplies rate_ frames.
        std::vector<std::int16_t> source_samples_;
        std::size_t source_start_frame_;
        double source_position_;

        bool valid_;

    public:
        ios_audio_output_stream(audio_driver *driver, const std::uint32_t sample_rate,
            const std::uint8_t channels, data_callback callback)
            : audio_output_stream(driver, sample_rate, channels)
            , unit_(nullptr)
            , callback_(std::move(callback))
            , rate_(sample_rate)
            , hardware_rate_(0)
            , chans_(channels ? channels : 1)
            , volume_(1.0f)
            , playing_(false)
            , source_frames_rendered_(0)
            , source_start_frame_(0)
            , source_position_(0.0)
            , valid_(false) {
            const double active_rate = ensure_audio_session();
            hardware_rate_ = static_cast<std::uint32_t>(std::llround(active_rate));
            if (hardware_rate_ == 0) hardware_rate_ = rate_;
            source_samples_.reserve(static_cast<std::size_t>(8192) * chans_);
            valid_ = setup_unit();
        }

        ~ios_audio_output_stream() override {
            if (unit_) {
                AudioOutputUnitStop(unit_);
                AudioUnitUninitialize(unit_);
                AudioComponentInstanceDispose(unit_);
                unit_ = nullptr;
            }
        }

        bool start() override {
            if (!valid_) {
                return false;
            }
            if (playing_.exchange(true)) {
                return true;
            }
            return AudioOutputUnitStart(unit_) == noErr;
        }

        bool stop() override {
            if (!valid_) {
                return false;
            }
            if (!playing_.exchange(false)) {
                return true;
            }
            return AudioOutputUnitStop(unit_) == noErr;
        }

        void pause() override {
            stop();
        }

        bool is_playing() override {
            return playing_.load();
        }

        bool is_pausing() override {
            return !playing_.load();
        }

        bool set_volume(const float volume) override {
            volume_.store(volume < 0.0f ? 0.0f : (volume > 1.0f ? 1.0f : volume));
            return true;
        }

        float get_volume() const override {
            return volume_.load();
        }

        bool current_frame_position(std::uint64_t *pos) override {
            if (pos) {
                *pos = source_frames_rendered_.load();
            }
            return true;
        }

    private:
        bool setup_unit() {
            AudioComponentDescription desc = {};
            desc.componentType = kAudioUnitType_Output;
            desc.componentSubType = kAudioUnitSubType_RemoteIO;
            desc.componentManufacturer = kAudioUnitManufacturer_Apple;

            AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
            if (!comp) {
                LOG_ERROR(DRIVER_AUD, "iOS audio: RemoteIO component not found");
                return false;
            }

            if (AudioComponentInstanceNew(comp, &unit_) != noErr) {
                LOG_ERROR(DRIVER_AUD, "iOS audio: failed to create RemoteIO instance");
                return false;
            }

            // Enable output on the output bus (element 0).
            const UInt32 enable = 1;
            AudioUnitSetProperty(unit_, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output,
                0, &enable, sizeof(enable));

            AudioStreamBasicDescription fmt = {};
            // This is the callback/client format. It must use the active hardware rate because
            // this backend performs the guest-to-hardware conversion itself below.
            fmt.mSampleRate = static_cast<Float64>(hardware_rate_);
            fmt.mFormatID = kAudioFormatLinearPCM;
            fmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
            fmt.mFramesPerPacket = 1;
            fmt.mChannelsPerFrame = chans_;
            fmt.mBitsPerChannel = 16;
            fmt.mBytesPerFrame = chans_ * sizeof(std::int16_t);
            fmt.mBytesPerPacket = fmt.mBytesPerFrame;

            if (AudioUnitSetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
                    0, &fmt, sizeof(fmt)) != noErr) {
                LOG_ERROR(DRIVER_AUD, "iOS audio: failed to set stream format ({} Hz, {} ch)", hardware_rate_, chans_);
                return false;
            }

            AURenderCallbackStruct cb = {};
            cb.inputProc = &ios_audio_output_stream::render_cb;
            cb.inputProcRefCon = this;
            AudioUnitSetProperty(unit_, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input,
                0, &cb, sizeof(cb));

            if (AudioUnitInitialize(unit_) != noErr) {
                LOG_ERROR(DRIVER_AUD, "iOS audio: failed to initialise RemoteIO unit");
                return false;
            }

            LOG_INFO(DRIVER_AUD, "iOS RemoteIO audio output ready (guest {} Hz -> route {} Hz, {} ch)", rate_, hardware_rate_, chans_);
            return true;
        }

        void ensure_source_frames(const std::size_t required_frames) {
            const std::size_t available_frames = source_samples_.size() / chans_ - source_start_frame_;
            if (available_frames >= required_frames) return;

            const std::size_t requested_frames = required_frames - available_frames;
            const std::size_t write_offset = source_samples_.size();
            source_samples_.resize(write_offset + requested_frames * chans_);
            std::size_t produced_frames = callback_ ? callback_(source_samples_.data() + write_offset, requested_frames) : 0;
            produced_frames = std::min(produced_frames, requested_frames);
            if (produced_frames < requested_frames) {
                std::memset(source_samples_.data() + write_offset + produced_frames * chans_, 0,
                    (requested_frames - produced_frames) * chans_ * sizeof(std::int16_t));
            }
        }

        void compact_source_frames() {
            if (source_start_frame_ < 2048) return;
            const std::size_t remaining_frames = source_samples_.size() / chans_ - source_start_frame_;
            std::memmove(source_samples_.data(), source_samples_.data() + source_start_frame_ * chans_,
                remaining_frames * chans_ * sizeof(std::int16_t));
            source_samples_.resize(remaining_frames * chans_);
            source_start_frame_ = 0;
        }

        void render_resampled(std::int16_t *out, const std::size_t output_frames) {
            if (!out || output_frames == 0) return;
            const double ratio = static_cast<double>(rate_) / static_cast<double>(hardware_rate_);
            const std::size_t required_frames = static_cast<std::size_t>(std::floor(source_position_ +
                (output_frames - 1) * ratio)) + 2;
            ensure_source_frames(required_frames);

            for (std::size_t frame = 0; frame < output_frames; ++frame) {
                const double source_at = source_position_ + frame * ratio;
                const std::size_t first = static_cast<std::size_t>(source_at);
                const float fraction = static_cast<float>(source_at - first);
                const std::int16_t *a = source_samples_.data() + (source_start_frame_ + first) * chans_;
                const std::int16_t *b = a + chans_;
                for (std::size_t channel = 0; channel < chans_; ++channel) {
                    const float interpolated = a[channel] + (b[channel] - a[channel]) * fraction;
                    out[frame * chans_ + channel] = static_cast<std::int16_t>(std::lrint(interpolated));
                }
            }

            source_position_ += output_frames * ratio;
            const std::size_t consumed_frames = static_cast<std::size_t>(source_position_);
            source_position_ -= consumed_frames;
            source_start_frame_ += consumed_frames;
            source_frames_rendered_.fetch_add(consumed_frames, std::memory_order_relaxed);
            compact_source_frames();
        }

        static OSStatus render_cb(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
            UInt32 bus, UInt32 num_frames, AudioBufferList *data) {
            ios_audio_output_stream *self = reinterpret_cast<ios_audio_output_stream *>(ref);

            // The stream format above is packed/interleaved, therefore RemoteIO supplies one
            // buffer. Treat an unexpected buffer list as silence instead of invoking the guest
            // callback twice and consuming audio at double speed.
            if (data->mNumberBuffers != 1 || !data->mBuffers[0].mData) {
                for (UInt32 b = 0; b < data->mNumberBuffers; ++b) {
                    if (data->mBuffers[b].mData) {
                        std::memset(data->mBuffers[b].mData, 0, data->mBuffers[b].mDataByteSize);
                    }
                }
                return noErr;
            }
            std::int16_t *out = reinterpret_cast<std::int16_t *>(data->mBuffers[0].mData);
            const std::size_t total_samples = data->mBuffers[0].mDataByteSize / sizeof(std::int16_t);
            const std::size_t output_frames = std::min<std::size_t>(num_frames, total_samples / self->chans_);
            self->render_resampled(out, output_frames);
            if (output_frames * self->chans_ < total_samples) {
                std::memset(out + output_frames * self->chans_, 0,
                    (total_samples - output_frames * self->chans_) * sizeof(std::int16_t));
            }

            const float vol = self->volume_.load();
            if (vol < 0.999f) {
                for (std::size_t i = 0; i < output_frames * self->chans_; i++) {
                    out[i] = static_cast<std::int16_t>(out[i] * vol);
                }
            }
            return noErr;
        }
    };

    std::unique_ptr<audio_output_stream> make_ios_audio_output_stream(audio_driver *driver,
        const std::uint32_t sample_rate, const std::uint8_t channels, data_callback callback) {
        return std::make_unique<ios_audio_output_stream>(driver, sample_rate, channels, std::move(callback));
    }
}
