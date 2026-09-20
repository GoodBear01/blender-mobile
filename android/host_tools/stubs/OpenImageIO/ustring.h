#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <type_traits>
#include <unordered_map>

/* Host-only stand-in for OpenImageIO::ustring.
 * Real ustring is an interned pointer and must stay trivially copyable so
 * blender::UString can live in std::atomic. */
namespace OpenImageIO {

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

class ustring {
 public:
  ustring() = default;
  explicit ustring(std::string_view v) : p_(intern(v)) {}
  explicit ustring(const char *v) : p_(v ? intern(std::string_view(v)) : nullptr) {}

  const char *c_str() const
  {
    return p_ ? p_->s.c_str() : nullptr;
  }
  const std::string &string() const
  {
    static const std::string empty;
    return p_ ? p_->s : empty;
  }
  size_t length() const
  {
    return p_ ? p_->s.size() : 0;
  }
  size_t size() const
  {
    return length();
  }
  bool empty() const
  {
    return !p_ || p_->s.empty();
  }
  uint64_t hash() const
  {
    return p_ ? p_->hash : 0;
  }
  char operator[](size_t i) const
  {
    return p_ ? p_->s[i] : '\0';
  }
  friend bool operator==(const ustring &a, const ustring &b)
  {
    return a.p_ == b.p_;
  }

 private:
  struct interned {
    std::string s;
    uint64_t hash = 0;
  };
  const interned *p_ = nullptr;

  static const interned *intern(std::string_view v)
  {
    static std::mutex mu;
    static std::unordered_map<std::string, std::unique_ptr<interned>> pool;
    std::lock_guard<std::mutex> lock(mu);
    std::string key(v);
    std::unique_ptr<interned> &slot = pool[key];
    if (!slot) {
      slot = std::make_unique<interned>();
      slot->s = std::move(key);
      slot->hash = Strutil::strhash64(slot->s.size(), slot->s.c_str());
    }
    return slot.get();
  }
};

static_assert(std::is_trivially_copyable_v<ustring>);

}  // namespace OpenImageIO
