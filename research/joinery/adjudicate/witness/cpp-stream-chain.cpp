#include <iostream>

int main() {
  Ledger led;
  std::cout << kBanner << "total=" << led.total() << "\n";
  return 0;
}
