#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

/* Minimal OpenImageIO ustring stand-in for host makesdna/makesrna.
 * The iOS OIIO install is not a macOS include tree. */
namespace OpenImageIO {

class ustring {
 public:
  ustring() = default;
  explicit ustring(std::string_view v) : s_(v) {}
  explicit ustring(const char *v) : s_(v ? v : "") {}

  const char *c_str() const
  {
    return s_.c_str();
  }
  const std::string &string() const
  {
    return s_;
  }
  size_t length() const
  {
    return s_.size();
  }
  size_t size() const
  {
    return s_.size();
  }
  bool empty() const
  {
    return s_.empty();
  }
  uint64_t hash() const
  {
    uint64_t h = 14695981039346656037ull;
    for (unsigned char c : s_) {
      h ^= c;
      h *= 1099511628211ull;
    }
    return h;
  }
  char operator[](size_t i) const
  {
    return s_[i];
  }
  friend bool operator==(const ustring &a, const ustring &b)
  {
    return a.s_ == b.s_;
  }

 private:
  std::string s_;
};

namespace Strutil {
constexpr uint64_t strhash64(size_t n, const char *s)
{
  uint64_t h = 14695981039346656037ull;
  for (size_t i = 0; i < n; ++i) {
    h ^= static_cast<unsigned char>(s[i]);
    h *= 1099511628211ull;
  }
  return h;
}
}  // namespace Strutil

}  // namespace OpenImageIO
