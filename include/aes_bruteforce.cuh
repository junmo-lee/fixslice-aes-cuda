#pragma once
#include <cuda_runtime.h>
#include <stdint.h>

// Bruteforce configuration
struct BruteforceConfig {
    uint8_t known_key_prefix[12];  // First 12 bytes of key (known)
    uint32_t search_start;          // Start of 4-byte search space
    uint32_t search_end;            // End of 4-byte search space
    uint8_t plaintext[16];          // Known plaintext
    uint8_t ciphertext[16];         // Target ciphertext
    bool found;                     // Flag if key is found
    uint8_t found_key[16];          // The found key
    uint32_t found_value;           // The found 4-byte suffix
};

// Launch bruteforce kernel
cudaError_t launch_bruteforce_kernel(
    BruteforceConfig* d_config,
    uint32_t start_value,
    uint32_t num_keys_to_test,
    int block_size,
    int grid_size,
    cudaStream_t stream = 0
);

// Host function to check if key produces correct ciphertext
bool verify_key_cpu(const uint8_t key[16], 
                    const uint8_t plaintext[16], 
                    const uint8_t ciphertext[16]);
