/*
 * The corpus program: a ledger that caches its own total.
 * push invalidates the cache, total rebuilds it and holds it until the
 * next push, and every file in this folder tells that same story.
 */
#include <cstdint>
#include <iostream>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

// A raw string literal, where the delimiter is part of the token's own
// spelling and the newline inside it is ordinary text.
static const char* kBanner = R"(ledger receipt
--------------
)";

class Ledger {
 public:
  Ledger() = default;

  explicit Ledger(const std::vector<std::int64_t>& seed) {
    for (std::size_t i = 0; i < seed.size(); i++) {
      push("seed" + std::to_string(i), seed[i]);
    }
  }

  std::size_t push(const std::string& tag, std::int64_t v) {
    const std::size_t at = rows_.size();
    rows_.push_back(v);
    tags_[tag] = at;
    total_.reset();
    return at;
  }

  std::int64_t total() {
    if (!total_.has_value()) {
      std::int64_t acc = 0;
      for (const auto r : rows_) {
        if (r > 0) acc += r;
      }
      total_ = acc;
    }
    return *total_;
  }

 private:
  std::vector<std::int64_t> rows_;
  std::unordered_map<std::string, std::size_t> tags_;
  std::optional<std::int64_t> total_;
};

int main() {
  Ledger led{{1, 2, 3}};
  led.push("late", 4);
  std::cout << kBanner << "total=" << led.total() << "\n";
  return 0;
}
