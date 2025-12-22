#pragma once
// Simple tag type for compile-time key bytes
template<unsigned char... Bytes>
struct StaticKey {
    static constexpr unsigned char data[sizeof...(Bytes)] = {Bytes...};
};
template<unsigned char... Bytes>
constexpr unsigned char StaticKey<Bytes...>::data[sizeof...(Bytes)];
