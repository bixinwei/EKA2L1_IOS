#pragma once

#include <filesystem>
#include <vector>

namespace eka2l1::ios::backup {
namespace fs = std::filesystem;

inline bool safe_relative(const fs::path &path) {
    if (path.empty() || path.is_absolute() || path.has_root_name() || path.has_root_directory()) return false;
    for (const auto &part : path) {
        if (part == ".." || part == "." || part.empty()) return false;
    }
    return true;
}

// Do not follow an existing symlink while replacing files from a backup.
inline bool safe_destination(const fs::path &root, const fs::path &rel) {
    if (!safe_relative(rel)) return false;
    auto current = root;
    for (const auto &part : rel) {
        current /= part;
        std::error_code ec;
        auto status = fs::symlink_status(current, ec);
        if (ec && ec != std::errc::no_such_file_or_directory) return false;
        if (fs::is_symlink(status)) return false;
    }
    return true;
}

enum class result { committed, rolled_back, recovery_required };

// All files must already have been extracted and CRC-checked. Original files
// are moved, not deleted; a failed commit restores them in reverse order.
inline result commit(const fs::path &root, const fs::path &staged,
                     const fs::path &saved, const std::vector<fs::path> &files) {
    struct change { fs::path relative; bool saved = false; bool installed = false; };
    std::vector<change> changes;
    changes.reserve(files.size());
    std::error_code ec;
    for (const auto &rel : files) {
        if (!safe_destination(root, rel) || !fs::is_regular_file(staged / rel, ec) || ec) {
            ec = std::make_error_code(std::errc::invalid_argument);
            break;
        }
        auto dest = root / rel;
        fs::create_directories(dest.parent_path(), ec);
        if (ec) break;
        changes.push_back({rel});
        auto &change = changes.back();
        const bool exists = fs::exists(dest, ec);
        if (ec) break;
        if (exists) {
            if (!fs::is_regular_file(dest, ec) || ec) {
                ec = std::make_error_code(std::errc::invalid_argument);
                break;
            }
            fs::create_directories((saved / rel).parent_path(), ec);
            if (ec) break;
            fs::rename(dest, saved / rel, ec);
            if (ec) break;
            change.saved = true;
        }
        fs::rename(staged / rel, dest, ec);
        if (ec) break;
        change.installed = true;
    }
    if (!ec) return result::committed;

    bool recovered = true;
    for (auto it = changes.rbegin(); it != changes.rend(); ++it) {
        std::error_code undo;
        if (it->installed) {
            fs::rename(root / it->relative, staged / it->relative, undo);
            if (undo) { recovered = false; continue; }
        }
        if (it->saved) {
            fs::rename(saved / it->relative, root / it->relative, undo);
            if (undo) recovered = false;
        }
    }
    // Caller MUST retain saved/staged and avoid restarting if recovery failed.
    return recovered ? result::rolled_back : result::recovery_required;
}
}
