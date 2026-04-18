#include <array>
#include <cstdint>
#include <fstream>
#include <stdexcept>
#include <string>

namespace {

constexpr std::size_t kBitstreamBytes = 256;
constexpr std::size_t kChunkBytes = 64;
constexpr std::size_t kWordsPerChunk = kChunkBytes / sizeof(std::uint32_t);
std::array<std::uint8_t, kBitstreamBytes> g_bitstream_bytes{};

std::uint32_t load_word_le(std::size_t byte_offset) {
  return static_cast<std::uint32_t>(g_bitstream_bytes[byte_offset + 0])
      | (static_cast<std::uint32_t>(g_bitstream_bytes[byte_offset + 1]) << 8)
      | (static_cast<std::uint32_t>(g_bitstream_bytes[byte_offset + 2]) << 16)
      | (static_cast<std::uint32_t>(g_bitstream_bytes[byte_offset + 3]) << 24);
}

}  // namespace

extern "C" {

void dice_vector_mul_bitstream_init(const char* bitstream_file) {
  g_bitstream_bytes.fill(0);

  if (bitstream_file == nullptr || bitstream_file[0] == '\0') {
    throw std::runtime_error("dice_vector_mul_bitstream_init: empty bitstream path");
  }

  std::ifstream stream(bitstream_file, std::ios::binary);
  if (!stream) {
    throw std::runtime_error(
        "dice_vector_mul_bitstream_init: could not open bitstream file '" +
        std::string(bitstream_file) + "'");
  }

  stream.read(reinterpret_cast<char*>(g_bitstream_bytes.data()),
              static_cast<std::streamsize>(g_bitstream_bytes.size()));
}

void dice_vector_mul_bitstream_get_chunk(
    unsigned int chunk_idx,
    unsigned int* w0,
    unsigned int* w1,
    unsigned int* w2,
    unsigned int* w3,
    unsigned int* w4,
    unsigned int* w5,
    unsigned int* w6,
    unsigned int* w7,
    unsigned int* w8,
    unsigned int* w9,
    unsigned int* w10,
    unsigned int* w11,
    unsigned int* w12,
    unsigned int* w13,
    unsigned int* w14,
    unsigned int* w15) {
  if (chunk_idx >= (kBitstreamBytes / kChunkBytes)) {
    throw std::runtime_error(
        "dice_vector_mul_bitstream_get_chunk: chunk index out of range");
  }

  unsigned int* outputs[kWordsPerChunk] = {
      w0,  w1,  w2,  w3,
      w4,  w5,  w6,  w7,
      w8,  w9,  w10, w11,
      w12, w13, w14, w15,
  };

  const std::size_t chunk_base = static_cast<std::size_t>(chunk_idx) * kChunkBytes;
  for (std::size_t word_idx = 0; word_idx < kWordsPerChunk; ++word_idx) {
    *outputs[word_idx] = load_word_le(chunk_base + word_idx * sizeof(std::uint32_t));
  }
}

}  // extern "C"
