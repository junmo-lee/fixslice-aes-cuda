# CUDA AES-128 Bitslice (32-way lanes) — `TMP` + `constexpr` secret keys

This repo provides:
- A 32-way **bitsliced AES-128** implementation in CUDA
- **Compile-time round keys** (no runtime key storage) using templates/`constexpr`
- **Implicit ShiftRows** (via column remapping) in the main rounds
- Tools for **input generation**, **unpacking**, and **verification**

## Build

```bash
cmake -S . -B build -DGPU_ARCH=90   # adjust SM (e.g. 86, 89)
cmake --build build -j
```

> Build prints ptxas info; expect `0 bytes lmem` for kernels.

## Generate inputs (control grid & block)

```bash
python3 tools/make_inputs.py --grid 2x1x1 --block 256x1x1 --seed 1
# writes inputs/run_YYYYmmdd_HHMMSS/{plaintexts.bin, plaintexts.hex, slices_u32_le.bin, meta.json}
```

- `groups = grid.x*grid.y*grid.z * block.x*block.y*block.z`
- Each thread processes **32** plaintexts (one 128-bit state in bitslice).
- Bitsliced input layout: `groups * 128` little-endian `uint32_t` slices.

## Run (full AES)

```bash
IN=inputs/run_*/slices_u32_le.bin
OUT=outputs/run_full_slices_u32_le.bin
./build/cuda-aes-full "$IN" "$OUT" 2x1x1 256x1x1
```

- Stores **bitsliced ciphertext** to `OUT`.

## Verify and unpack to standard bytes

```bash
python3 tools/verify_outputs.py \
  --meta inputs/run_*/meta.json \
  --slices_out "$OUT" \
  --keyhex 2b7e151628aed2a6abf7158809cf4f3c
```

- Also writes:
  - `outputs/ciphertexts_from_cuda.bin` (unpacked CUDA output)
  - `outputs/ciphertexts_from_python.bin` (Python AES-128 reference)

## Other test targets

- S-box only:
  ```bash
  ./build/cuda-aes-sbox-only inputs/.../slices_u32_le.bin outputs/sbox_only.bin 256
  ```
- MixColumns only:
  ```bash
  ./build/cuda-aes-mix-only inputs/.../slices_u32_le.bin outputs/mix_only.bin 256
  ```

## Compile-time keys (no runtime storage)

- Round keys are computed in templates (`include/aes_keys.hpp`).  
- AddRoundKey is emitted as compile-time `~reg` for key-bit=1 (`xor` with all-ones), using **no** registers or memory for keys.
- Edit the key in `src/aes_full_kernel.cu` inside `run_aes_bs_full()`:
  ```cpp
  using MyKey = StaticKey<
      0x2B,0x7E,0x15,0x16, 0x28,0xAE,0xD2,0xA6, 0xAB,0xF7,0x15,0x88, 0x09,0xCF,0x4F,0x3C
  >;
  ```

## Notes
- ShiftRows in the **main rounds** is handled implicitly by calling MixColumns with bytes `{0,5,10,15}`, `{4,9,14,3}`, `{8,13,2,7}`, `{12,1,6,11}`.  
- Final round does SubBytes + ShiftRows only, then applies the last round key. A register-only permutation is used once.

## Bruteforce Implementation (Educational)

This repository includes AES-128 bruteforce implementations for educational purposes:

- **Single GPU**: `./build/cuda-aes-bruteforce` (no MPI required)
- **Multi-GPU/Node**: `./build/cuda-aes-bruteforce-mpi` (uses MPI for distribution)

**See [BRUTEFORCE_KR.md](BRUTEFORCE_KR.md) for detailed documentation in Korean.**

### Quick Start

```bash
# Generate test case
python3 tools/gen_bruteforce_test.py

# Run bruteforce (searches last 4 bytes of key)
./build/cuda-aes-bruteforce \
    00112233445566778899aabbccddeeff \
    8df4e9aac5c7573a27d8d055d6e4d64b \
    2b7e151628aed2a6abf71588
```

⚠️ **Warning**: Full AES-128 bruteforce (2^128 keys) is computationally infeasible. This demo searches only the last 4 bytes (2^32 keys) for educational purposes.

