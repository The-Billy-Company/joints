#include <string>

struct Ledger {
  long total;
  void seed(const std::vector<long>& s) {
    for (std::size_t i = 0; i < s.size(); i++) {
      push(s[i]);
    }
  }
  void push(long v) { total = total + v; }
};
