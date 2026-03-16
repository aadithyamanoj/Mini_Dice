#include <cstdint>
#include <random>

namespace {

constexpr std::uint32_t kDefaultSeed = 0xD1CEu;
std::mt19937 g_rng(kDefaultSeed);

std::uint32_t lane_mul(std::uint32_t a, std::uint32_t b) {
  return ((a & 0xFFu) * (b & 0xFFu)) & 0xFFu;
}

void write_case(
    const std::uint32_t a[4],
    const std::uint32_t b[4],
    std::uint32_t* a0,
    std::uint32_t* a1,
    std::uint32_t* a2,
    std::uint32_t* a3,
    std::uint32_t* b0,
    std::uint32_t* b1,
    std::uint32_t* b2,
    std::uint32_t* b3,
    std::uint32_t* y0,
    std::uint32_t* y1,
    std::uint32_t* y2,
    std::uint32_t* y3) {
  *a0 = a[0];
  *a1 = a[1];
  *a2 = a[2];
  *a3 = a[3];
  *b0 = b[0];
  *b1 = b[1];
  *b2 = b[2];
  *b3 = b[3];
  *y0 = lane_mul(a[0], b[0]);
  *y1 = lane_mul(a[1], b[1]);
  *y2 = lane_mul(a[2], b[2]);
  *y3 = lane_mul(a[3], b[3]);
}

}  // namespace

extern "C" {

void dice_vector_mul_golden_init(unsigned int seed) {
  g_rng.seed(seed);
}

void dice_vector_mul_golden_directed_case(
    unsigned int* a0,
    unsigned int* a1,
    unsigned int* a2,
    unsigned int* a3,
    unsigned int* b0,
    unsigned int* b1,
    unsigned int* b2,
    unsigned int* b3,
    unsigned int* y0,
    unsigned int* y1,
    unsigned int* y2,
    unsigned int* y3) {
  const std::uint32_t a[4] = {3u, 5u, 2u, 7u};
  const std::uint32_t b[4] = {4u, 6u, 8u, 1u};
  write_case(a, b, a0, a1, a2, a3, b0, b1, b2, b3, y0, y1, y2, y3);
}

void dice_vector_mul_golden_random_case(
    unsigned int* a0,
    unsigned int* a1,
    unsigned int* a2,
    unsigned int* a3,
    unsigned int* b0,
    unsigned int* b1,
    unsigned int* b2,
    unsigned int* b3,
    unsigned int* y0,
    unsigned int* y1,
    unsigned int* y2,
    unsigned int* y3) {
  std::uniform_int_distribution<std::uint32_t> dist(0u, 15u);
  std::uint32_t a[4];
  std::uint32_t b[4];

  for (int lane = 0; lane < 4; ++lane) {
    a[lane] = dist(g_rng);
    b[lane] = dist(g_rng);
  }

  write_case(a, b, a0, a1, a2, a3, b0, b1, b2, b3, y0, y1, y2, y3);
}

}  // extern "C"
