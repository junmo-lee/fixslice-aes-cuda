#include <cuda_runtime.h>
#include <stdint.h>
#include <stdio.h>
#include "aes_bruteforce.cuh"

// Simple AES S-box
__constant__ unsigned char d_sbox[256] = {
    0x63,0x7C,0x77,0x7B,0xF2,0x6B,0x6F,0xC5,0x30,0x01,0x67,0x2B,0xFE,0xD7,0xAB,0x76,
    0xCA,0x82,0xC9,0x7D,0xFA,0x59,0x47,0xF0,0xAD,0xD4,0xA2,0xAF,0x9C,0xA4,0x72,0xC0,
    0xB7,0xFD,0x93,0x26,0x36,0x3F,0xF7,0xCC,0x34,0xA5,0xE5,0xF1,0x71,0xD8,0x31,0x15,
    0x04,0xC7,0x23,0xC3,0x18,0x96,0x05,0x9A,0x07,0x12,0x80,0xE2,0xEB,0x27,0xB2,0x75,
    0x09,0x83,0x2C,0x1A,0x1B,0x6E,0x5A,0xA0,0x52,0x3B,0xD6,0xB3,0x29,0xE3,0x2F,0x84,
    0x53,0xD1,0x00,0xED,0x20,0xFC,0xB1,0x5B,0x6A,0xCB,0xBE,0x39,0x4A,0x4C,0x58,0xCF,
    0xD0,0xEF,0xAA,0xFB,0x43,0x4D,0x33,0x85,0x45,0xF9,0x02,0x7F,0x50,0x3C,0x9F,0xA8,
    0x51,0xA3,0x40,0x8F,0x92,0x9D,0x38,0xF5,0xBC,0xB6,0xDA,0x21,0x10,0xFF,0xF3,0xD2,
    0xCD,0x0C,0x13,0xEC,0x5F,0x97,0x44,0x17,0xC4,0xA7,0x7E,0x3D,0x64,0x5D,0x19,0x73,
    0x60,0x81,0x4F,0xDC,0x22,0x2A,0x90,0x88,0x46,0xEE,0xB8,0x14,0xDE,0x5E,0x0B,0xDB,
    0xE0,0x32,0x3A,0x0A,0x49,0x06,0x24,0x5C,0xC2,0xD3,0xAC,0x62,0x91,0x95,0xE4,0x79,
    0xE7,0xC8,0x37,0x6D,0x8D,0xD5,0x4E,0xA9,0x6C,0x56,0xF4,0xEA,0x65,0x7A,0xAE,0x08,
    0xBA,0x78,0x25,0x2E,0x1C,0xA6,0xB4,0xC6,0xE8,0xDD,0x74,0x1F,0x4B,0xBD,0x8B,0x8A,
    0x70,0x3E,0xB5,0x66,0x48,0x03,0xF6,0x0E,0x61,0x35,0x57,0xB9,0x86,0xC1,0x1D,0x9E,
    0xE1,0xF8,0x98,0x11,0x69,0xD9,0x8E,0x94,0x9B,0x1E,0x87,0xE9,0xCE,0x55,0x28,0xDF,
    0x8C,0xA1,0x89,0x0D,0xBF,0xE6,0x42,0x68,0x41,0x99,0x2D,0x0F,0xB0,0x54,0xBB,0x16
};

__constant__ unsigned char d_rcon[11] = {
    0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1B,0x36
};

// Device function: AES key expansion
__device__ void aes_key_expansion(const uint8_t* key, uint32_t* w) {
    // Copy initial key
    for (int i = 0; i < 4; i++) {
        w[i] = ((uint32_t)key[4*i] << 24) | ((uint32_t)key[4*i+1] << 16) |
               ((uint32_t)key[4*i+2] << 8) | (uint32_t)key[4*i+3];
    }
    
    // Generate remaining round keys
    for (int i = 4; i < 44; i++) {
        uint32_t temp = w[i-1];
        if (i % 4 == 0) {
            // RotWord
            temp = ((temp << 8) | (temp >> 24)) & 0xFFFFFFFF;
            // SubWord
            temp = ((uint32_t)d_sbox[(temp >> 24) & 0xFF] << 24) |
                   ((uint32_t)d_sbox[(temp >> 16) & 0xFF] << 16) |
                   ((uint32_t)d_sbox[(temp >> 8) & 0xFF] << 8) |
                   ((uint32_t)d_sbox[temp & 0xFF]);
            // XOR with Rcon
            temp ^= ((uint32_t)d_rcon[i/4] << 24);
        }
        w[i] = w[i-4] ^ temp;
    }
}

// Device function: SubBytes
__device__ void sub_bytes(uint8_t* state) {
    for (int i = 0; i < 16; i++) {
        state[i] = d_sbox[state[i]];
    }
}

// Device function: ShiftRows
__device__ void shift_rows(uint8_t* state) {
    uint8_t temp;
    // Row 1: shift left by 1
    temp = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = temp;
    // Row 2: shift left by 2
    temp = state[2]; state[2] = state[10]; state[10] = temp;
    temp = state[6]; state[6] = state[14]; state[14] = temp;
    // Row 3: shift left by 3
    temp = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = state[3]; state[3] = temp;
}

// Device function: GF(2^8) multiplication
__device__ uint8_t gmul(uint8_t a, uint8_t b) {
    uint8_t p = 0;
    for (int i = 0; i < 8; i++) {
        if (b & 1) p ^= a;
        uint8_t hi_bit_set = a & 0x80;
        a <<= 1;
        if (hi_bit_set) a ^= 0x1B;
        b >>= 1;
    }
    return p;
}

// Device function: MixColumns
__device__ void mix_columns(uint8_t* state) {
    for (int i = 0; i < 4; i++) {
        uint8_t s0 = state[i*4];
        uint8_t s1 = state[i*4 + 1];
        uint8_t s2 = state[i*4 + 2];
        uint8_t s3 = state[i*4 + 3];
        
        state[i*4]     = gmul(s0, 2) ^ gmul(s1, 3) ^ s2 ^ s3;
        state[i*4 + 1] = s0 ^ gmul(s1, 2) ^ gmul(s2, 3) ^ s3;
        state[i*4 + 2] = s0 ^ s1 ^ gmul(s2, 2) ^ gmul(s3, 3);
        state[i*4 + 3] = gmul(s0, 3) ^ s1 ^ s2 ^ gmul(s3, 2);
    }
}

// Device function: AddRoundKey
__device__ void add_round_key(uint8_t* state, const uint32_t* w, int round) {
    for (int i = 0; i < 4; i++) {
        uint32_t word = w[round * 4 + i];
        state[i*4]     ^= (word >> 24) & 0xFF;
        state[i*4 + 1] ^= (word >> 16) & 0xFF;
        state[i*4 + 2] ^= (word >> 8) & 0xFF;
        state[i*4 + 3] ^= word & 0xFF;
    }
}

// Device function: AES-128 encryption
__device__ void aes_encrypt(const uint8_t* plaintext, uint8_t* ciphertext, const uint8_t* key) {
    uint32_t w[44];
    uint8_t state[16];
    
    // Copy plaintext to state
    for (int i = 0; i < 16; i++) {
        state[i] = plaintext[i];
    }
    
    // Key expansion
    aes_key_expansion(key, w);
    
    // Initial round
    add_round_key(state, w, 0);
    
    // Main rounds (1-9)
    for (int round = 1; round < 10; round++) {
        sub_bytes(state);
        shift_rows(state);
        mix_columns(state);
        add_round_key(state, w, round);
    }
    
    // Final round (10)
    sub_bytes(state);
    shift_rows(state);
    add_round_key(state, w, 10);
    
    // Copy state to ciphertext
    for (int i = 0; i < 16; i++) {
        ciphertext[i] = state[i];
    }
}

// Device function: Compare two 16-byte arrays
__device__ bool compare_bytes(const uint8_t* a, const uint8_t* b) {
    for (int i = 0; i < 16; i++) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

// CUDA kernel: Bruteforce AES keys
__global__ void bruteforce_kernel(BruteforceConfig* config, uint32_t start_value, uint32_t num_keys) {
    uint32_t tid = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t stride = gridDim.x * blockDim.x;
    
    uint8_t test_key[16];
    uint8_t result[16];
    
    // Copy known prefix
    for (int i = 0; i < 12; i++) {
        test_key[i] = config->known_key_prefix[i];
    }
    
    // Test keys in this thread's range
    for (uint32_t i = tid; i < num_keys; i += stride) {
        // Check if already found by another thread
        if (config->found) return;
        
        uint32_t test_value = start_value + i;
        
        // Set last 4 bytes
        test_key[12] = (test_value >> 24) & 0xFF;
        test_key[13] = (test_value >> 16) & 0xFF;
        test_key[14] = (test_value >> 8) & 0xFF;
        test_key[15] = test_value & 0xFF;
        
        // Encrypt with test key
        aes_encrypt(config->plaintext, result, test_key);
        
        // Compare with target ciphertext
        if (compare_bytes(result, config->ciphertext)) {
            // Found the key!
            config->found = true;
            config->found_value = test_value;
            for (int j = 0; j < 16; j++) {
                config->found_key[j] = test_key[j];
            }
            return;
        }
    }
}

// Host function to launch kernel
cudaError_t launch_bruteforce_kernel(
    BruteforceConfig* d_config,
    uint32_t start_value,
    uint32_t num_keys_to_test,
    int block_size,
    int grid_size,
    cudaStream_t stream)
{
    bruteforce_kernel<<<grid_size, block_size, 0, stream>>>(d_config, start_value, num_keys_to_test);
    return cudaGetLastError();
}
