#include <mpi.h>
#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include "aes_bruteforce.cuh"

#define CUDA_CHECK(call) \
    do { \
        cudaError_t err = call; \
        if (err != cudaSuccess) { \
            fprintf(stderr, "CUDA error at %s:%d: %s\n", __FILE__, __LINE__, \
                    cudaGetErrorString(err)); \
            MPI_Abort(MPI_COMM_WORLD, 1); \
        } \
    } while(0)

#define MPI_CHECK(call) \
    do { \
        int err = call; \
        if (err != MPI_SUCCESS) { \
            char error_string[MPI_MAX_ERROR_STRING]; \
            int length; \
            MPI_Error_string(err, error_string, &length); \
            fprintf(stderr, "MPI error at %s:%d: %s\n", __FILE__, __LINE__, error_string); \
            MPI_Abort(MPI_COMM_WORLD, 1); \
        } \
    } while(0)

// Parse hex string to bytes
void hex_to_bytes(const char* hex, uint8_t* bytes, int len) {
    for (int i = 0; i < len; i++) {
        sscanf(hex + 2*i, "%2hhx", &bytes[i]);
    }
}

// Print bytes as hex
void print_hex(const char* label, const uint8_t* data, int len) {
    printf("%s", label);
    for (int i = 0; i < len; i++) {
        printf("%02x", data[i]);
    }
    printf("\n");
}

// Print progress
void print_progress(int rank, uint32_t keys_tested, uint32_t total_keys, double elapsed_time) {
    double progress = (double)keys_tested / total_keys * 100.0;
    double keys_per_sec = keys_tested / elapsed_time;
    printf("[Rank %d] Progress: %.2f%% (%u/%u keys, %.2f Mkeys/s, %.1fs elapsed)\n",
           rank, progress, keys_tested, total_keys, keys_per_sec / 1e6, elapsed_time);
    fflush(stdout);
}

int main(int argc, char** argv) {
    int rank, size;
    
    // Initialize MPI
    MPI_CHECK(MPI_Init(&argc, &argv));
    MPI_CHECK(MPI_Comm_rank(MPI_COMM_WORLD, &rank));
    MPI_CHECK(MPI_Comm_size(MPI_COMM_WORLD, &size));
    
    // Check arguments
    if (argc < 4) {
        if (rank == 0) {
            printf("Usage: %s <plaintext_hex> <ciphertext_hex> <key_prefix_hex_24chars>\n", argv[0]);
            printf("Example: %s 00112233445566778899aabbccddeeff 69c4e0d86a7b0430d8cdb78070b4c55a 2b7e151628aed2a6abf71588\n", argv[0]);
            printf("\nSearches last 4 bytes (32 bits) of AES-128 key.\n");
            printf("Total search space: 2^32 = 4,294,967,296 keys\n");
        }
        MPI_Finalize();
        return 1;
    }
    
    // Parse input
    BruteforceConfig h_config;
    memset(&h_config, 0, sizeof(BruteforceConfig));
    
    hex_to_bytes(argv[1], h_config.plaintext, 16);
    hex_to_bytes(argv[2], h_config.ciphertext, 16);
    hex_to_bytes(argv[3], h_config.known_key_prefix, 12);
    
    if (rank == 0) {
        printf("=== AES-128 Bruteforce (MPI + CUDA) ===\n");
        printf("MPI Processes: %d\n", size);
        print_hex("Plaintext:  ", h_config.plaintext, 16);
        print_hex("Ciphertext: ", h_config.ciphertext, 16);
        print_hex("Key prefix: ", h_config.known_key_prefix, 12);
        printf("Searching:  ????????\n");
        printf("Search space: 2^32 = 4,294,967,296 keys\n");
        printf("Keys per process: %u\n\n", (uint32_t)(0xFFFFFFFFU / size + 1));
    }
    
    // Get GPU info
    int device_count;
    CUDA_CHECK(cudaGetDeviceCount(&device_count));
    int device = rank % device_count;
    CUDA_CHECK(cudaSetDevice(device));
    
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, device));
    printf("[Rank %d] Using GPU %d: %s (SM %d.%d)\n", 
           rank, device, prop.name, prop.major, prop.minor);
    
    // Allocate device memory
    BruteforceConfig* d_config;
    CUDA_CHECK(cudaMalloc(&d_config, sizeof(BruteforceConfig)));
    
    // Calculate key range for this process
    uint64_t total_keys = 0x100000000ULL;  // 2^32
    uint64_t keys_per_proc = (total_keys + size - 1) / size;
    uint64_t start_key = rank * keys_per_proc;
    uint64_t end_key = start_key + keys_per_proc;
    if (end_key > total_keys) end_key = total_keys;
    
    uint32_t local_start = (uint32_t)start_key;
    uint32_t local_count = (uint32_t)(end_key - start_key);
    
    printf("[Rank %d] Key range: 0x%08x to 0x%08x (%u keys)\n",
           rank, local_start, (uint32_t)(end_key - 1), local_count);
    
    // Kernel configuration
    int block_size = 256;
    int grid_size = (prop.multiProcessorCount * 2);  // 2 blocks per SM
    uint32_t keys_per_batch = grid_size * block_size * 10000;  // Keys to test per kernel launch
    
    printf("[Rank %d] Kernel config: grid=%d, block=%d, batch_size=%u\n",
           rank, grid_size, block_size, keys_per_batch);
    
    // Start timer
    double start_time = MPI_Wtime();
    double last_progress_time = start_time;
    
    uint32_t processed = 0;
    bool found_global = false;
    uint8_t found_key_global[16];
    
    // Main search loop
    while (processed < local_count && !found_global) {
        uint32_t batch_size = (processed + keys_per_batch <= local_count) ? 
                              keys_per_batch : (local_count - processed);
        
        // Copy config to device
        h_config.found = false;
        CUDA_CHECK(cudaMemcpy(d_config, &h_config, sizeof(BruteforceConfig), cudaMemcpyHostToDevice));
        
        // Launch kernel
        CUDA_CHECK(launch_bruteforce_kernel(d_config, local_start + processed, batch_size, 
                                            block_size, grid_size, 0));
        CUDA_CHECK(cudaDeviceSynchronize());
        
        // Check result
        CUDA_CHECK(cudaMemcpy(&h_config, d_config, sizeof(BruteforceConfig), cudaMemcpyDeviceToHost));
        
        if (h_config.found) {
            printf("\n[Rank %d] *** KEY FOUND! ***\n", rank);
            print_hex("[Rank %d] Key: ", h_config.found_key, 16);
            printf("\n");
            
            // Notify all processes
            MPI_CHECK(MPI_Bcast(&h_config.found, 1, MPI_C_BOOL, rank, MPI_COMM_WORLD));
            MPI_CHECK(MPI_Bcast(h_config.found_key, 16, MPI_UNSIGNED_CHAR, rank, MPI_COMM_WORLD));
            
            found_global = true;
            memcpy(found_key_global, h_config.found_key, 16);
            break;
        }
        
        processed += batch_size;
        
        // Check if another process found it
        int found_flag = 0;
        MPI_CHECK(MPI_Iprobe(MPI_ANY_SOURCE, 0, MPI_COMM_WORLD, &found_flag, MPI_STATUS_IGNORE));
        if (found_flag) {
            MPI_CHECK(MPI_Bcast(&found_global, 1, MPI_C_BOOL, MPI_ANY_SOURCE, MPI_COMM_WORLD));
            if (found_global) {
                MPI_CHECK(MPI_Bcast(found_key_global, 16, MPI_UNSIGNED_CHAR, MPI_ANY_SOURCE, MPI_COMM_WORLD));
                break;
            }
        }
        
        // Print progress every 5 seconds
        double current_time = MPI_Wtime();
        if (current_time - last_progress_time >= 5.0) {
            print_progress(rank, processed, local_count, current_time - start_time);
            last_progress_time = current_time;
        }
    }
    
    // Wait for all processes
    MPI_Barrier(MPI_COMM_WORLD);
    
    double end_time = MPI_Wtime();
    double elapsed = end_time - start_time;
    
    // Gather statistics
    uint32_t all_processed[size];
    MPI_CHECK(MPI_Gather(&processed, 1, MPI_UNSIGNED, all_processed, 1, MPI_UNSIGNED, 0, MPI_COMM_WORLD));
    
    if (rank == 0) {
        printf("\n=== Results ===\n");
        if (found_global) {
            printf("Status: KEY FOUND!\n");
            print_hex("Key: ", found_key_global, 16);
        } else {
            printf("Status: Key not found in search space\n");
        }
        
        uint64_t total_tested = 0;
        for (int i = 0; i < size; i++) {
            total_tested += all_processed[i];
        }
        
        printf("\nStatistics:\n");
        printf("  Total time: %.2f seconds\n", elapsed);
        printf("  Total keys tested: %lu (%.2f%%)\n", total_tested, 
               (double)total_tested / total_keys * 100.0);
        printf("  Overall throughput: %.2f Mkeys/s\n", total_tested / elapsed / 1e6);
        printf("  Per-process throughput: %.2f Mkeys/s\n", total_tested / elapsed / 1e6 / size);
        
        printf("\nPer-process statistics:\n");
        for (int i = 0; i < size; i++) {
            printf("  Rank %d: %u keys tested\n", i, all_processed[i]);
        }
    }
    
    // Cleanup
    CUDA_CHECK(cudaFree(d_config));
    MPI_Finalize();
    
    return found_global ? 0 : 1;
}
