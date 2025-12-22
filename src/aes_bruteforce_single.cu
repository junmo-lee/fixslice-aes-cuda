// Single-GPU AES-128 Bruteforce (without MPI)
// Demonstrates brute-force attack on a limited key space

#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include "../include/aes_bruteforce.cuh"

// Function declaration from aes_bruteforce_kernel.cu
__global__ void bruteforce_kernel(BruteforceConfig* config, uint32_t start_key, uint32_t end_key);

void parse_hex_string(const char* hex_str, unsigned char* bytes, size_t byte_count) {
    for (size_t i = 0; i < byte_count; i++) {
        sscanf(hex_str + 2*i, "%2hhx", &bytes[i]);
    }
}

void print_hex(const char* label, const unsigned char* data, size_t len) {
    printf("%s", label);
    for (size_t i = 0; i < len; i++) {
        printf("%02x", data[i]);
    }
    printf("\n");
}

int main(int argc, char** argv) {
    printf("=== AES-128 Single-GPU Bruteforce ===\n\n");
    
    if (argc != 4) {
        printf("Usage: %s <plaintext_hex> <ciphertext_hex> <known_key_prefix_hex>\n", argv[0]);
        printf("Example: %s 00112233445566778899aabbccddeeff 69c4e0d86a7b0430d8cdb78070b4c55a 2b7e151628aed2a6abf71588\n", argv[0]);
        printf("\nThis will search for the last 4 bytes of the AES-128 key.\n");
        return 1;
    }
    
    // Parse command line arguments
    unsigned char plaintext[16];
    unsigned char ciphertext[16];
    unsigned char known_key_prefix[12];
    
    parse_hex_string(argv[1], plaintext, 16);
    parse_hex_string(argv[2], ciphertext, 16);
    parse_hex_string(argv[3], known_key_prefix, 12);
    
    printf("Plaintext:  ");
    print_hex("", plaintext, 16);
    printf("Ciphertext: ");
    print_hex("", ciphertext, 16);
    printf("Known key prefix (12 bytes): ");
    print_hex("", known_key_prefix, 12);
    printf("\nSearching for the last 4 bytes...\n\n");
    
    // Allocate device memory
    BruteforceConfig* d_config;
    cudaMalloc(&d_config, sizeof(BruteforceConfig));
    
    // Initialize config on host
    BruteforceConfig h_config;
    memcpy(h_config.known_key_prefix, known_key_prefix, 12);
    memcpy(h_config.plaintext, plaintext, 16);
    memcpy(h_config.ciphertext, ciphertext, 16);
    h_config.found = false;
    memset(h_config.found_key, 0, 16);
    h_config.found_value = 0;
    h_config.search_start = 0x00000000;
    h_config.search_end = 0xFFFFFFFF;
    
    // Copy config to device
    cudaMemcpy(d_config, &h_config, sizeof(BruteforceConfig), cudaMemcpyHostToDevice);
    
    // Launch parameters
    const uint32_t threads_per_block = 256;
    const uint32_t blocks = 1024;  // Can be tuned based on GPU
    const uint32_t keys_per_launch = threads_per_block * blocks;
    
    printf("GPU Configuration:\n");
    printf("  Threads per block: %u\n", threads_per_block);
    printf("  Blocks: %u\n", blocks);
    printf("  Keys per kernel launch: %u\n", keys_per_launch);
    printf("  Total search space: 2^32 = 4,294,967,296 keys\n\n");
    
    // Start timing
    clock_t start_time = clock();
    uint64_t total_keys_tested = 0;
    uint32_t current_key = h_config.search_start;
    bool found = false;
    
    printf("Starting bruteforce...\n");
    printf("(Press Ctrl+C to stop)\n\n");
    
    // Main bruteforce loop
    while (current_key < h_config.search_end && !found) {
        uint32_t batch_end = current_key + keys_per_launch;
        if (batch_end > h_config.search_end || batch_end < current_key) {
            batch_end = h_config.search_end;
        }
        
        // Launch kernel
        bruteforce_kernel<<<blocks, threads_per_block>>>(d_config, current_key, batch_end);
        
        // Check for key found every few batches
        if (total_keys_tested % (keys_per_launch * 10) == 0) {
            cudaMemcpy(&h_config, d_config, sizeof(BruteforceConfig), cudaMemcpyDeviceToHost);
            
            if (h_config.found) {
                found = true;
                break;
            }
            
            // Print progress
            clock_t current_time = clock();
            double elapsed = (double)(current_time - start_time) / CLOCKS_PER_SEC;
            double keys_per_sec = total_keys_tested / elapsed;
            double percent = (double)total_keys_tested / 4294967296.0 * 100.0;
            
            printf("\rProgress: %.2f%% | Tested: %lu keys | Speed: %.2f Mkeys/s | Time: %.1fs",
                   percent, total_keys_tested, keys_per_sec / 1e6, elapsed);
            fflush(stdout);
        }
        
        total_keys_tested += (batch_end - current_key);
        current_key = batch_end;
    }
    
    // Final check
    cudaMemcpy(&h_config, d_config, sizeof(BruteforceConfig), cudaMemcpyDeviceToHost);
    
    clock_t end_time = clock();
    double total_elapsed = (double)(end_time - start_time) / CLOCKS_PER_SEC;
    
    printf("\n\n=== Results ===\n");
    if (h_config.found) {
        printf("✓ KEY FOUND!\n");
        printf("Full key: ");
        print_hex("", h_config.found_key, 16);
        printf("Keys tested: %lu\n", total_keys_tested);
        printf("Time elapsed: %.2f seconds\n", total_elapsed);
        printf("Average speed: %.2f Mkeys/s\n", total_keys_tested / total_elapsed / 1e6);
    } else {
        printf("✗ Key not found in search space.\n");
        printf("Keys tested: %lu\n", total_keys_tested);
        printf("Time elapsed: %.2f seconds\n", total_elapsed);
        printf("Average speed: %.2f Mkeys/s\n", total_keys_tested / total_elapsed / 1e6);
    }
    
    // Cleanup
    cudaFree(d_config);
    
    return h_config.found ? 0 : 1;
}
