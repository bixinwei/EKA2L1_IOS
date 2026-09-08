#include <common/queue.h>

#include <cassert>
#include <vector>

int main() {
    eka2l1::cp_queue<int> queue;
    queue.push(2);
    queue.push(7);
    queue.push(4);

    // Mirrors the window-server capture dispatch: end() is never dereferenced.
    std::vector<int> reverse;
    for (auto it = queue.end(); it != queue.begin();) {
        --it;
        reverse.push_back(*it);
    }
    assert(reverse.size() == 3);

    for (auto it = queue.begin(); it != queue.end();) {
        if (*it == 7) it = queue.erase(it);
        else ++it;
    }
    queue.resort();
    assert(queue.size() == 2);
    assert(queue.top() == 4);
}
