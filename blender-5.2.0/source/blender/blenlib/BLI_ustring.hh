/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <unordered_map>

#include "BLI_fixed_string.hh"
#include "BLI_hash.hh"
#include "BLI_string_ref.hh"

namespace blender {

namespace ustring_detail {

constexpr uint64_t strhash64(const size_t n, const char *s)
{
  uint64_t h = 14695981039346656037ull;
  for (size_t i = 0; i < n; ++i) {
    h ^= static_cast<unsigned char>(s[i]);
    h *= 1099511628211ull;
  }
  return h;
}

/* Interned pointer, matching OpenImageIO::ustring layout/semantics enough
 * for Blender. Kept independent of OIIO headers so host tools and iOS can
 * compile when those headers are missing or use a versioned namespace. */
class interned_ustring {
 public:
  interned_ustring() = default;
  explicit interned_ustring(const std::string_view v) : p_(intern(v)) {}
  explicit interned_ustring(const char *v) : p_(v ? intern(std::string_view(v)) : nullptr) {}

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
  char operator[](const size_t i) const
  {
    return p_ ? p_->s[i] : '\0';
  }
  friend bool operator==(const interned_ustring &a, const interned_ustring &b)
  {
    return a.p_ == b.p_;
  }

 private:
  struct interned {
    std::string s;
    uint64_t hash = 0;
  };
  const interned *p_ = nullptr;

  static const interned *intern(const std::string_view v)
  {
    static std::mutex mu;
    static std::unordered_map<std::string, std::unique_ptr<interned>> pool;
    std::lock_guard<std::mutex> lock(mu);
    std::string key(v);
    std::unique_ptr<interned> &slot = pool[key];
    if (!slot) {
      slot = std::make_unique<interned>();
      slot->s = std::move(key);
      slot->hash = strhash64(slot->s.size(), slot->s.c_str());
    }
    return slot.get();
  }
};

}  // namespace ustring_detail

/**
 * Interned unique string. API matches the OpenImageIO-backed desktop type.
 */
class UString {
 private:
  ustring_detail::interned_ustring ustr_;

 public:
  UString() = default;
  explicit UString(const StringRef str) : ustr_(std::string_view(str)) {}

  static UString from_ptr_noinline(const char *str);

  StringRefNull ref() const
  {
    return StringRefNull(ustr_.c_str(), ustr_.length());
  }

  const std::string &string() const
  {
    return ustr_.string();
  }

  const char *c_str() const
  {
    return ustr_.c_str();
  }

  friend bool operator==(const UString &a, const UString &b)
  {
    return a.ustr_ == b.ustr_;
  }

  friend bool operator==(const UString &a, const StringRef b)
  {
    return a.ref() == b;
  }

  uint64_t hash() const
  {
    return ustr_.hash();
  }

  int64_t size() const
  {
    return int64_t(ustr_.size());
  }

  bool is_empty() const
  {
    return ustr_.empty();
  }

  char operator[](const int64_t i) const
  {
    BLI_assert(i >= 0 && i <= this->size());
    return ustr_[i];
  }
};

template<> struct DefaultHash<UString> {
  uint64_t operator()(const UString &value) const
  {
    return value.hash();
  }

  constexpr uint64_t operator()(const StringRef value) const
  {
    return ustring_detail::strhash64(size_t(value.size()), value.data());
  }
};

template<FixedString FStr> inline UString operator""_ustr()
{
  static std::atomic<const char *> static_chars;
  const char *chars = static_chars.load(std::memory_order_relaxed);
  if (chars == nullptr) [[unlikely]] {
    chars = UString::from_ptr_noinline(FStr.data).c_str();
    static_chars.store(chars, std::memory_order_relaxed);
  }
  return UString::from_ptr_noinline(chars);
}

inline std::string_view format_as(UString str)
{
  return str.string();
}

}  // namespace blender

namespace fmt {

template<> struct is_range<blender::UString, char> : std::false_type {};

}  // namespace fmt
