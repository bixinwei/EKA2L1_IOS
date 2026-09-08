/*
 * Copyright (c) 2026 EKA2L1 Team.
 * This file is part of EKA2L1 project and is licensed under GPL-3.0-or-later.
 */
#import "TouchMappingEditorViewController.h"
#import "TouchMappingStore.h"
#import "KeybindStore.h"
#import "KeybindCaptureViewController.h"

@implementation TouchMappingEditorViewController {
    uint32_t _uid;
    NSString *_gameName;
    __weak UIView *_gameView;
    void (^_mappingsChanged)(void);
    void (^_editingChanged)(BOOL);
    NSMutableArray<NSMutableDictionary *> *_mappings;
    NSArray<NSString *> *_pendingTokens;
    UILabel *_hint;
    UIView *_bar;
    NSMutableDictionary<NSString *, UIButton *> *_markers;
}

- (instancetype)initWithUid:(uint32_t)uid name:(NSString *)name gameView:(UIView *)gameView
              mappingsChanged:(void (^)(void))mappingsChanged editingChanged:(void (^)(BOOL))editingChanged {
    self = [super init];
    if (self) {
        _uid = uid;
        _gameName = [name copy];
        _gameView = gameView;
        _mappingsChanged = [mappingsChanged copy];
        _editingChanged = [editingChanged copy];
        // JSON deserialization returns immutable dictionaries. The editor updates x/y while
        // dragging, so make every record mutable (a shallow mutable array copy crashes here).
        _mappings = [NSMutableArray array];
        for (NSDictionary *mapping in [TouchMappingStore mappingsForUid:uid]) {
            [_mappings addObject:[mapping mutableCopy]];
        }
        _markers = [NSMutableDictionary dictionary];
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.multipleTouchEnabled = YES;
    [self buildBar];
    [self rebuildMarkers];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_editingChanged) _editingChanged(YES);
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Presenting the controller-button capture sheet temporarily covers this editor; it
    // must not re-enable game input in that interval. Only the editor's own dismissal ends
    // the protected editing session.
    if (self.isBeingDismissed && _editingChanged) _editingChanged(NO);
}

- (void)dealloc {
    if (_editingChanged) _editingChanged(NO);
}

- (void)buildBar {
    _bar = [[UIView alloc] init];
    _bar.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
    _bar.layer.cornerRadius = 14;
    _bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_bar];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"Controller Touch Mapping";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [_bar addSubview:title];

    _hint = [[UILabel alloc] init];
    _hint.text = @"Add a button, then tap its target in the game.";
    _hint.textColor = [UIColor colorWithWhite:0.78 alpha:1.0];
    _hint.font = [UIFont systemFontOfSize:12];
    _hint.numberOfLines = 2;
    _hint.translatesAutoresizingMaskIntoConstraints = NO;
    [_bar addSubview:_hint];

    UIButton *(^button)(NSString *, SEL) = ^UIButton *(NSString *text, SEL action) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:text forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        b.backgroundColor = [UIColor colorWithRed:0.12 green:0.43 blue:0.86 alpha:1.0];
        b.layer.cornerRadius = 9;
        [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        b.translatesAutoresizingMaskIntoConstraints = NO;
        [_bar addSubview:b];
        return b;
    };
    UIButton *add = button(@"+ Add", @selector(addMapping));
    UIButton *clear = button(@"Clear", @selector(clearMappings));
    clear.backgroundColor = [UIColor colorWithRed:0.55 green:0.18 blue:0.18 alpha:1.0];
    UIButton *done = button(@"Done", @selector(done));

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *preferredWidth = [_bar.widthAnchor constraintEqualToConstant:500];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [_bar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [_bar.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_bar.widthAnchor constraintLessThanOrEqualToAnchor:safe.widthAnchor constant:-24],
        preferredWidth,
        [_bar.heightAnchor constraintEqualToConstant:78],
        [title.leadingAnchor constraintEqualToAnchor:_bar.leadingAnchor constant:14],
        [title.topAnchor constraintEqualToAnchor:_bar.topAnchor constant:10],
        [_hint.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_hint.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3],
        [_hint.trailingAnchor constraintLessThanOrEqualToAnchor:add.leadingAnchor constant:-10],
        [done.trailingAnchor constraintEqualToAnchor:_bar.trailingAnchor constant:-10],
        [done.centerYAnchor constraintEqualToAnchor:_bar.centerYAnchor],
        [done.widthAnchor constraintEqualToConstant:62], [done.heightAnchor constraintEqualToConstant:38],
        [clear.trailingAnchor constraintEqualToAnchor:done.leadingAnchor constant:-7],
        [clear.centerYAnchor constraintEqualToAnchor:done.centerYAnchor],
        [clear.widthAnchor constraintEqualToConstant:62], [clear.heightAnchor constraintEqualToConstant:38],
        [add.trailingAnchor constraintEqualToAnchor:clear.leadingAnchor constant:-7],
        [add.centerYAnchor constraintEqualToAnchor:done.centerYAnchor],
        [add.widthAnchor constraintEqualToConstant:62], [add.heightAnchor constraintEqualToConstant:38],
    ]];
}

- (CGRect)gameRect {
    UIView *game = _gameView;
    return game ? [game convertRect:game.bounds toView:self.view] : CGRectZero;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self positionMarkers];
}

- (void)positionMarkers {
    CGRect rect = [self gameRect];
    for (NSMutableDictionary *mapping in _mappings) {
        UIButton *marker = _markers[mapping[@"id"]];
        if (!marker || CGRectIsEmpty(rect)) continue;
        const BOOL isDisk = [mapping[@"type"] isEqualToString:@"dpad"];
        const CGFloat diameter = isDisk ? MAX(72.0, MIN(190.0, rect.size.width * [mapping[@"size"] doubleValue] * 2.0)) : 54.0;
        marker.bounds = CGRectMake(0, 0, diameter, diameter);
        marker.layer.cornerRadius = diameter / 2.0;
        marker.center = CGPointMake(CGRectGetMinX(rect) + rect.size.width * [mapping[@"x"] doubleValue],
                                    CGRectGetMinY(rect) + rect.size.height * [mapping[@"y"] doubleValue]);
    }
}

- (void)rebuildMarkers {
    for (UIView *marker in _markers.allValues) [marker removeFromSuperview];
    [_markers removeAllObjects];
    for (NSMutableDictionary *mapping in _mappings) {
        UIButton *marker = [UIButton buttonWithType:UIButtonTypeCustom];
        marker.frame = CGRectMake(0, 0, 54, 54);
        marker.backgroundColor = [UIColor colorWithRed:0.12 green:0.48 blue:1.0 alpha:0.88];
        marker.layer.borderColor = UIColor.whiteColor.CGColor;
        marker.layer.borderWidth = 2.0;
        marker.layer.cornerRadius = 27.0;
        marker.clipsToBounds = YES;
        const BOOL isDisk = [mapping[@"type"] isEqualToString:@"dpad"];
        marker.titleLabel.font = [UIFont systemFontOfSize:isDisk ? 22 : 11 weight:UIFontWeightBold];
        marker.titleLabel.numberOfLines = isDisk ? 3 : 2;
        marker.titleLabel.textAlignment = NSTextAlignmentCenter;
        [marker setTitle:isDisk ? @"↑\n←  →\n↓" : [KeybindStore controllerComboName:mapping[@"tokens"]] forState:UIControlStateNormal];
        marker.accessibilityIdentifier = mapping[@"id"];
        UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragMarker:)];
        drag.maximumNumberOfTouches = 1; // leave two-finger gestures exclusively to direction-disk scaling
        [marker addGestureRecognizer:drag];
        if (isDisk) [marker addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(scaleDirectionDisk:)]];
        UILongPressGestureRecognizer *remove = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(removeMarker:)];
        remove.minimumPressDuration = 0.55;
        [marker addGestureRecognizer:remove];
        [self.view addSubview:marker];
        _markers[mapping[@"id"]] = marker;
    }
    [self positionMarkers];
}

- (NSMutableDictionary *)mappingForIdentifier:(NSString *)identifier {
    for (NSMutableDictionary *mapping in _mappings) if ([mapping[@"id"] isEqual:identifier]) return mapping;
    return nil;
}

- (void)persist {
    [TouchMappingStore saveMappings:_mappings forUid:_uid];
    if (_mappingsChanged) _mappingsChanged();
}

- (void)addMapping {
    if (_pendingTokens) return;
    UIAlertController *choice = [UIAlertController alertControllerWithTitle:@"Add touch mapping" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [choice addAction:[UIAlertAction actionWithTitle:@"Button target" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self beginButtonMapping]; }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Direction disk" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self addDirectionDisk]; }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    choice.popoverPresentationController.sourceView = _bar;
    choice.popoverPresentationController.sourceRect = _bar.bounds;
    [self presentViewController:choice animated:YES completion:nil];
}

- (void)beginButtonMapping {
    __weak typeof(self) weakSelf = self;
    KeybindCaptureViewController *capture = [[KeybindCaptureViewController alloc] initForController:YES completion:^(NSArray *combo) {
        TouchMappingEditorViewController *selfRef = weakSelf;
        if (!selfRef || combo.count == 0) return;
        selfRef->_pendingTokens = [combo copy];
        selfRef->_hint.text = [NSString stringWithFormat:@"Tap the target for %@.", [KeybindStore controllerComboName:combo]];
        selfRef->_hint.textColor = [UIColor colorWithRed:0.35 green:0.80 blue:1.0 alpha:1.0];
    }];
    [self presentViewController:capture animated:YES completion:nil];
}

- (void)addDirectionDisk {
    NSMutableDictionary *disk = [@{ @"id": [[NSUUID UUID] UUIDString], @"type": @"dpad",
                                    @"x": @0.5, @"y": @0.5, @"size": @0.13 } mutableCopy];
    [_mappings addObject:disk];
    _hint.text = @"Drag the direction disk. Pinch it to resize.";
    _hint.textColor = [UIColor colorWithWhite:0.78 alpha:1.0];
    [self persist];
    [self rebuildMarkers];
}

- (void)clearMappings {
    if (_mappings.count == 0) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear touch mappings?"
        message:@"This only removes mappings for this game." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self->_mappings removeAllObjects];
        [self persist];
        [self rebuildMarkers];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)dragMarker:(UIPanGestureRecognizer *)pan {
    UIButton *marker = (UIButton *)pan.view;
    NSMutableDictionary *mapping = [self mappingForIdentifier:marker.accessibilityIdentifier];
    CGRect rect = [self gameRect];
    if (!mapping || CGRectIsEmpty(rect)) return;
    CGPoint point = [pan locationInView:self.view];
    point.x = MAX(CGRectGetMinX(rect), MIN(CGRectGetMaxX(rect), point.x));
    point.y = MAX(CGRectGetMinY(rect), MIN(CGRectGetMaxY(rect), point.y));
    marker.center = point;
    mapping[@"x"] = @((point.x - CGRectGetMinX(rect)) / rect.size.width);
    mapping[@"y"] = @((point.y - CGRectGetMinY(rect)) / rect.size.height);
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) [self persist];
}

- (void)scaleDirectionDisk:(UIPinchGestureRecognizer *)pinch {
    UIButton *marker = (UIButton *)pinch.view;
    NSMutableDictionary *mapping = [self mappingForIdentifier:marker.accessibilityIdentifier];
    if (!mapping || ![mapping[@"type"] isEqualToString:@"dpad"]) return;
    if (pinch.state == UIGestureRecognizerStateBegan) marker.accessibilityValue = [mapping[@"size"] stringValue];
    const CGFloat initial = marker.accessibilityValue.doubleValue;
    mapping[@"size"] = @(MAX(0.04, MIN(0.30, initial * pinch.scale)));
    [self positionMarkers];
    if (pinch.state == UIGestureRecognizerStateEnded || pinch.state == UIGestureRecognizerStateCancelled || pinch.state == UIGestureRecognizerStateFailed) {
        marker.accessibilityValue = nil;
        [self persist];
    }
}

- (void)removeMarker:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    UIButton *marker = (UIButton *)press.view;
    NSMutableDictionary *mapping = [self mappingForIdentifier:marker.accessibilityIdentifier];
    if (!mapping) return;
    NSString *name = [mapping[@"type"] isEqualToString:@"dpad"] ? @"Direction disk" : [KeybindStore controllerComboName:mapping[@"tokens"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove mapping?" message:name preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self->_mappings removeObject:mapping];
        [self persist];
        [self rebuildMarkers];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_pendingTokens) { [super touchesEnded:touches withEvent:event]; return; }
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:self.view];
    CGRect rect = [self gameRect];
    if (!CGRectContainsPoint(rect, point)) return;
    CGFloat x = (point.x - CGRectGetMinX(rect)) / rect.size.width;
    CGFloat y = (point.y - CGRectGetMinY(rect)) / rect.size.height;
    NSMutableDictionary *mapping = [@{ @"id": [[NSUUID UUID] UUIDString], @"type": @"button", @"tokens": _pendingTokens,
                                        @"x": @(x), @"y": @(y) } mutableCopy];
    [_mappings addObject:mapping];
    _pendingTokens = nil;
    _hint.text = @"Drag a marker to move it. Long-press one to remove it.";
    _hint.textColor = [UIColor colorWithWhite:0.78 alpha:1.0];
    [self persist];
    [self rebuildMarkers];
}

@end
