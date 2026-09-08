#include <ios/backup_transaction.h>
#include <cassert>
#include <chrono>
#include <fstream>
#include <iostream>

using namespace eka2l1::ios::backup;
static void write(const fs::path &p, const char *value) {
    fs::create_directories(p.parent_path());
    std::ofstream(p) << value;
}
static std::string read(const fs::path &p) {
    std::ifstream f(p);
    return {std::istreambuf_iterator<char>(f), {}};
}
int main() {
    auto temp = fs::temp_directory_path() / ("eka-backup-test-" +
        std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    auto root = temp / "live", staged = temp / "new", saved = temp / "old";
    fs::create_directories(temp);
    assert(!safe_relative("../escape"));
    assert(!safe_relative("/absolute"));
    assert(!safe_relative("a/../b"));
    assert(safe_relative("drives/c/a..b"));

    write(root / "a", "original-a");
    write(root / "unrelated", "keep");
    write(staged / "a", "replacement-a");
    write(staged / "nested/b", "new-b");
    assert(commit(root, staged, saved, {"a", "nested/b"}) == result::committed);
    assert(read(root / "a") == "replacement-a");
    assert(read(root / "nested/b") == "new-b");
    assert(read(root / "unrelated") == "keep");
    assert(read(saved / "a") == "original-a");

    // First file is installed, second cannot be read: restore the first file.
    auto stage2 = temp / "new2", save2 = temp / "old2";
    write(stage2 / "a", "bad-transaction");
    assert(commit(root, stage2, save2, {"a", "missing"}) == result::rolled_back);
    assert(read(root / "a") == "replacement-a");
    assert(read(stage2 / "a") == "bad-transaction");

    // Roll back a newly created file as well as an overwritten one.
    write(stage2 / "new-file", "temporary");
    assert(commit(root, stage2, save2, {"a", "new-file", "missing"}) == result::rolled_back);
    assert(!fs::exists(root / "new-file"));
    assert(read(root / "a") == "replacement-a");

    // Directory/file conflicts must not destroy an existing directory.
    fs::create_directories(root / "directory");
    write(stage2 / "directory", "not-a-directory");
    assert(commit(root, stage2, save2, {"a", "directory"}) == result::rolled_back);
    assert(fs::is_directory(root / "directory"));
    assert(read(root / "a") == "replacement-a");

    assert(commit(root, stage2, save2, {"a", "../escape"}) == result::rolled_back);
    assert(read(root / "a") == "replacement-a");
    std::error_code ec;
    fs::create_directory_symlink(temp, root / "link", ec);
    if (!ec) assert(!safe_destination(root, "link/outside"));
    else std::cout << "Symlink test skipped (host permission)\n";

    fs::remove_all(temp); // only this test's uniquely named temporary fixture
    std::cout << "Backup transaction tests passed\n";
}
