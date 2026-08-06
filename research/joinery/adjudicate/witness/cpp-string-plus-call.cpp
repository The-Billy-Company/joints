#include <string>

struct Ledger {
  long total;
  void seed(const std::vector<long>& s) {
    for (std::size_t i = 0; i < s.size(); i++) {
      push("seed" + std::to_string(i), s[i]);
    }
  }
  void push(const std::string& tag, long v) { total = total + v; }
};
