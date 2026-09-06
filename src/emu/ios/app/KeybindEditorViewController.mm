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
#import "KeybindEditorViewController.h"
#import "KeybindStore.h"
#import "KeybindCaptureViewController.h"

// ===========================================================================
// Per-action editor: keyboard slots + controller slots for one action.
// ===========================================================================
@interface EKAKeybindActionViewController : UITableViewController
- (instancetype)initWithAction:(EKAAction)action model:(NSMutableDictionary *)model
                           onSave:(void (^)(void))onSave;
@end

@interface PhoneKeyMappingViewController ()
@end

static NSArray<NSDictionary *> *EKAPhoneMappingItems(void) {
    return @[
        @{ @"key": @"164", @"title": @"Left Softkey" }, @{ @"key": @"165", @"title": @"Right Softkey" },
        @{ @"key": @"16", @"title": @"Up" }, @{ @"key": @"17", @"title": @"Down" },
        @{ @"key": @"14", @"title": @"Left" }, @{ @"key": @"15", @"title": @"Right" },
        @{ @"key": @"167", @"title": @"Centre / Select" },
        @{ @"key": @"menu", @"title": @"Menu" }, @{ @"key": @"clear", @"title": @"Clear" },
        @{ @"key": @"1", @"title": @"Phone 1" }, @{ @"key": @"2", @"title": @"Phone 2" }, @{ @"key": @"3", @"title": @"Phone 3" },
        @{ @"key": @"4", @"title": @"Phone 4" }, @{ @"key": @"5", @"title": @"Phone 5" }, @{ @"key": @"6", @"title": @"Phone 6" },
        @{ @"key": @"7", @"title": @"Phone 7" }, @{ @"key": @"8", @"title": @"Phone 8" }, @{ @"key": @"9", @"title": @"Phone 9" },
        @{ @"key": @"*", @"title": @"Phone *" }, @{ @"key": @"0", @"title": @"Phone 0" }, @{ @"key": @"#", @"title": @"Phone #" }
    ];
}

@implementation PhoneKeyMappingViewController {
    uint32_t _uid;
    void (^_onChange)(void);
    NSMutableDictionary *_phone;
    NSArray<NSString *> *_profileNames;
    NSString *_activeProfile;
}

- (instancetype)initWithUid:(uint32_t)uid onChange:(void (^)(void))onChange {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _uid = uid;
        _onChange = [onChange copy];
        _profileNames = [KeybindStore phoneKeyProfileNamesForUid:uid];
        _activeProfile = [KeybindStore activePhoneKeyProfileForUid:uid];
        _phone = [KeybindStore phoneBindingMapForUid:uid profileName:_activeProfile];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Phone Key Mapping";
}

- (void)reloadProfiles {
    _profileNames = [KeybindStore phoneKeyProfileNamesForUid:_uid];
    _activeProfile = [KeybindStore activePhoneKeyProfileForUid:_uid];
    _phone = [KeybindStore phoneBindingMapForUid:_uid profileName:_activeProfile];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? _profileNames.count + 1 : EKAPhoneMappingItems().count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Mapping Profiles" : @"Phone Keys";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"Profiles are saved per game. Create one for each controller or game layout, then select the active profile."
                        : @"Tap a phone key, then press the controller button or combination that should trigger it.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (indexPath.section == 0) {
        if (indexPath.row == _profileNames.count) {
            cell.textLabel.text = @"Create New Profile…";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        NSString *name = _profileNames[indexPath.row];
        cell.textLabel.text = name;
        cell.detailTextLabel.text = [name isEqualToString:_activeProfile] ? @"Active" : nil;
        cell.accessoryType = [name isEqualToString:_activeProfile] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return cell;
    }
    NSDictionary *item = EKAPhoneMappingItems()[indexPath.row];
    NSString *key = item[@"key"];
    cell.textLabel.text = item[@"title"];
    NSArray *tokens = _phone[key];
    cell.detailTextLabel.text = tokens.count ? [KeybindStore controllerComboName:tokens] : @"Not set";
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (indexPath.row < _profileNames.count) {
            [KeybindStore setActivePhoneKeyProfile:_profileNames[indexPath.row] forUid:_uid];
            [self reloadProfiles];
            [self.tableView reloadData];
            if (_onChange) _onChange();
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Mapping Profile" message:@"The current profile will be copied so you can adjust it." preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"Profile name"; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *name = alert.textFields.firstObject.text;
            if (![KeybindStore createPhoneKeyProfile:name copyingProfile:self->_activeProfile forUid:self->_uid]) {
                UIAlertController *error = [UIAlertController alertControllerWithTitle:@"Cannot Create Profile" message:@"Use a unique, non-empty profile name." preferredStyle:UIAlertControllerStyleAlert];
                [error addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:error animated:YES completion:nil];
                return;
            }
            [self reloadProfiles];
            [self.tableView reloadData];
            if (self->_onChange) self->_onChange();
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSDictionary *item = EKAPhoneMappingItems()[indexPath.row];
    NSString *key = item[@"key"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:item[@"title"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Press Controller Button…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        KeybindCaptureViewController *cap = [[KeybindCaptureViewController alloc] initForController:YES completion:^(NSArray *combo) {
            if (combo.count) self->_phone[key] = combo;
            else [self->_phone removeObjectForKey:key];
            [KeybindStore savePhoneBindingMap:self->_phone profileName:self->_activeProfile forUid:self->_uid];
            [self.tableView reloadData];
            if (self->_onChange) self->_onChange();
        }];
        [self presentViewController:cap animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self->_phone removeObjectForKey:key];
        [KeybindStore savePhoneBindingMap:self->_phone profileName:self->_activeProfile forUid:self->_uid];
        [self.tableView reloadData];
        if (self->_onChange) self->_onChange();
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    sheet.popoverPresentationController.sourceView = cell;
    sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath API_AVAILABLE(ios(11.0)) {
    if (indexPath.section != 0 || indexPath.row >= _profileNames.count || _profileNames.count <= 1) return nil;
    NSString *name = _profileNames[indexPath.row];
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction *action, UIView *view, void (^complete)(BOOL)) {
        BOOL deleted = [KeybindStore deletePhoneKeyProfile:name forUid:self->_uid];
        if (deleted) {
            [self reloadProfiles];
            [self.tableView reloadData];
            if (self->_onChange) self->_onChange();
        }
        complete(deleted);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}
@end

@implementation EKAKeybindActionViewController {
    EKAAction _action;
    NSString *_actKey;
    NSMutableDictionary *_model;
    void (^_onSave)(void);
}

- (instancetype)initWithAction:(EKAAction)action model:(NSMutableDictionary *)model onSave:(void (^)(void))onSave {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _action = action;
        _actKey = @(action).stringValue;
        _model = model;
        _onSave = [onSave copy];
        // Ensure a mutable entry exists for this action.
        if (![_model[_actKey] isKindOfClass:[NSMutableDictionary class]]) {
            _model[_actKey] = [NSMutableDictionary dictionaryWithDictionary:(_model[_actKey] ?: @{ @"kb": @[], @"ctrl": @[] })];
        }
        for (NSString *k in @[@"kb", @"ctrl"]) {
            if (![_model[_actKey][k] isKindOfClass:[NSMutableArray class]]) {
                _model[_actKey][k] = [NSMutableArray arrayWithArray:(_model[_actKey][k] ?: @[])];
            }
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = EKAActionName(_action);
}

- (NSArray *)slotsForKey:(NSString *)key { return _model[_actKey][key]; }

- (NSArray *)comboAtSection:(NSInteger)section row:(NSInteger)row {
    NSArray *slots = [self slotsForKey:(section == 0 ? @"kb" : @"ctrl")];
    return (row < (NSInteger)slots.count) ? slots[row] : @[];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return (s == 0) ? [KeybindStore maxKeyboardSlots] : [KeybindStore maxControllerSlots];
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return (s == 0) ? @"Keyboard" : @"Controller";
}

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == 1) return @"Tap a slot to set it by pressing a key/button — hold two together for a combo (e.g. Shift+Enter, X+Start).";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    NSString *label = (ip.section == 0) ? @"Keyboard" : @"Controller";
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %ld", label, (long)(ip.row + 1)];
    NSArray *combo = [self comboAtSection:ip.section row:ip.row];
    NSString *name = (ip.section == 0) ? [KeybindStore keyComboName:combo]
                                        : [KeybindStore controllerComboName:combo];
    cell.detailTextLabel.text = name.length ? name : @"Not set";
    cell.detailTextLabel.textColor = name.length ? [UIColor labelColor] : [UIColor tertiaryLabelColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)setSlotKey:(NSString *)key index:(NSInteger)i value:(NSArray *)value {
    NSMutableArray *slots = _model[_actKey][key];
    while ((NSInteger)slots.count <= i) {
        [slots addObject:@[]];
    }
    slots[i] = value ?: @[];
    if (_onSave) _onSave();
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    BOOL isCtrl = (ip.section == 1);
    NSString *key = isCtrl ? @"ctrl" : @"kb";

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:(isCtrl ? @"Press Controller Button…" : @"Press Key…")
                                              style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        KeybindCaptureViewController *cap = [[KeybindCaptureViewController alloc] initForController:isCtrl
            completion:^(NSArray *combo) {
                if (combo.count) {
                    [self setSlotKey:key index:ip.row value:combo];
                    [self.tableView reloadData];
                }
            }];
        [self presentViewController:cap animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *a) {
            [self setSlotKey:key index:ip.row value:@[]];
            [self.tableView reloadData];
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [t cellForRowAtIndexPath:ip];
    sheet.popoverPresentationController.sourceView = cell;
    sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

// ===========================================================================
// Action list.
// ===========================================================================
@implementation KeybindEditorViewController {
    uint32_t _uid;
    NSString *_scope;
    void (^_onChange)(void);
    NSMutableDictionary *_model;
}

- (instancetype)initWithUid:(uint32_t)uid scopeName:(NSString *)scopeName onChange:(void (^)(void))onChange {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _uid = uid;
        _scope = [scopeName copy];
        _onChange = [onChange copy];
        _model = [KeybindStore editingModelForUid:uid];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Keybinds";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];   // refresh summaries after returning from an action editor
}

- (void)save {
    [KeybindStore saveModel:_model forUid:_uid];
    if (_onChange) _onChange();
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return (s == 0) ? EKAActionCount : 1;
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return (s == 0) ? [NSString stringWithFormat:@"%@ Bindings", _scope] : nil;
}

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        return (_uid == 0) ? @"These bindings apply to every game (and work even when the on-screen layout is None)."
                           : @"These bindings apply only to this game, overriding the global ones.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = (_uid == 0) ? @"Reset to Defaults" : @"Reset to Global";
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    EKAAction act = (EKAAction)ip.row;
    cell.textLabel.text = EKAActionName(act);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    NSDictionary *entry = _model[@(act).stringValue];
    NSMutableArray *kbNames = [NSMutableArray array];
    for (NSArray *slot in entry[@"kb"]) {
        NSString *n = [KeybindStore keyComboName:slot];
        if (n.length) [kbNames addObject:n];
    }
    NSMutableArray *ctrlNames = [NSMutableArray array];
    for (NSArray *slot in entry[@"ctrl"]) {
        NSString *n = [KeybindStore controllerComboName:slot];
        if (n.length) [ctrlNames addObject:n];
    }
    NSString *kb = kbNames.count ? [kbNames componentsJoinedByString:@", "] : @"—";
    NSString *ct = ctrlNames.count ? [ctrlNames componentsJoinedByString:@", "] : @"—";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"⌨ %@   🎮 %@", kb, ct];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) {
        [self confirmReset];
        return;
    }
    EKAKeybindActionViewController *vc =
        [[EKAKeybindActionViewController alloc] initWithAction:(EKAAction)ip.row model:_model
                                                        onSave:^{ [self save]; }];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)confirmReset {
    NSString *msg = (_uid == 0) ? @"Restore all global keybinds to their defaults?"
                                : @"Remove this game's keybind override and use the global bindings?";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Keybinds" message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *a) {
            [KeybindStore resetForUid:self->_uid];
            self->_model = [KeybindStore editingModelForUid:self->_uid];
            [self.tableView reloadData];
            if (self->_onChange) self->_onChange();
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
