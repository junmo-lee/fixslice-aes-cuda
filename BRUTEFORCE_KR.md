# AES-128 Bruteforce Implementation

이 프로그램은 AES-128 암호화에 대한 브루트포스 공격을 시연하는 교육용/연구용 도구입니다.

## ⚠️ 중요 경고

**실제 AES-128 키에 대한 완전한 브루트포스는 현실적으로 불가능합니다!**
- 전체 키 공간: 2^128 ≈ 3.4 × 10^38 키
- 현재 세계 최고 슈퍼컴퓨터로도 수십억 년이 소요됩니다

이 구현은 다음의 교육 목적으로 제공됩니다:
- 병렬 컴퓨팅 기법 학습
- CUDA/MPI 프로그래밍 연습
- 암호학 보안 강도 이해

## 사용 방법

### 1. 단일 GPU 버전 (MPI 불필요)

가장 간단한 버전으로, 단일 GPU만 사용합니다:

```bash
./build/cuda-aes-bruteforce <plaintext_hex> <ciphertext_hex> <known_key_prefix_hex>
```

**예제:**
```bash
# 테스트 케이스 생성
python3 tools/gen_bruteforce_test.py

# 브루트포스 실행 (마지막 4바이트 탐색)
./build/cuda-aes-bruteforce \
    00112233445566778899aabbccddeeff \
    8df4e9aac5c7573a27d8d055d6e4d64b \
    2b7e151628aed2a6abf71588
```

### 2. MPI 분산 버전 (다중 노드/GPU)

여러 노드에서 병렬로 실행:

```bash
mpirun -np <num_processes> ./build/cuda-aes-bruteforce-mpi \
    <plaintext_hex> <ciphertext_hex> <known_key_prefix_hex>
```

## MPI 환경 문제 해결

### hwloc 토폴로지 오류

MIG (Multi-Instance GPU) 모드나 특정 환경에서 다음 오류가 발생할 수 있습니다:

```
hwloc: Topology does not contain any PU, aborting!
```

**해결 방법 1: hwloc 비활성화**
```bash
export OMPI_MCA_hwloc_base_binding_policy=none
mpirun --mca hwloc_base_binding_policy none -np 4 ./build/cuda-aes-bruteforce-mpi ...
```

**해결 방법 2: 단일 GPU 버전 사용**
```bash
# MPI 없이 단일 GPU로 실행
./build/cuda-aes-bruteforce ...
```

**해결 방법 3: root로 실행 (권장하지 않음)**
```bash
mpirun --allow-run-as-root -np 4 ./build/cuda-aes-bruteforce-mpi ...
```

## 프로그램 구조

### 키 공간 분할

- **전체 키 크기**: 16바이트 (128비트)
- **알려진 prefix**: 처음 12바이트 (예: `2b7e151628aed2a6abf71588`)
- **탐색 공간**: 마지막 4바이트 (2^32 = 4,294,967,296 키)

### 구현 파일

1. **`src/aes_bruteforce_single.cu`** - 단일 GPU 버전
   - MPI 의존성 없음
   - 간단한 구조
   - 로컬 머신에서 테스트용

2. **`src/aes_bruteforce_mpi.cu`** - MPI 분산 버전
   - 여러 노드/프로세스 지원
   - 자동 작업 분산
   - 키 발견 시 모든 프로세스에 통보

3. **`src/aes_bruteforce_kernel.cu`** - CUDA 커널
   - 디바이스 측 AES-128 구현
   - 병렬 키 테스트
   - S-box, 키 확장, 전체 10라운드

4. **`include/aes_bruteforce.cuh`** - 헤더
   - 설정 구조체
   - 함수 선언

## 성능

### 예상 처리량 (NVIDIA A100)

- **단일 GPU**: 약 1-2 Gkeys/s
- **4x A100**: 약 4-8 Gkeys/s (MPI)
- **8x A100**: 약 8-16 Gkeys/s (MPI)

### 예상 시간 (2^32 키 공간)

- **1 Gkeys/s**: 약 1.2시간
- **4 Gkeys/s**: 약 18분
- **10 Gkeys/s**: 약 7분

### 최적화 팁

1. **스레드/블록 조정**
   ```cpp
   const uint32_t threads_per_block = 256;  // 128, 256, 512 테스트
   const uint32_t blocks = 1024;             // GPU에 따라 조정
   ```

2. **더 큰 배치 처리**
   ```cpp
   keys_per_launch = threads_per_block * blocks;  // 증가시켜 보기
   ```

3. **GPU별 최적화**
   - V100: blocks = 512-1024
   - A100: blocks = 1024-2048
   - H100: blocks = 2048-4096

## 테스트

### 빠른 테스트 (작은 키 공간)

마지막 2바이트만 탐색 (65,536 키):

```python
# 수동으로 헤더 파일에서 search_end를 수정
# h_config.search_end = 0x0000FFFF;  // 마지막 2바이트만
```

### 실제 테스트

```bash
# 1. 테스트 케이스 생성
python3 tools/gen_bruteforce_test.py

# 2. 단일 GPU로 실행
./build/cuda-aes-bruteforce \
    00112233445566778899aabbccddeeff \
    8df4e9aac5c7573a27d8d055d6e4d64b \
    2b7e151628aed2a6abf71588

# 3. 진행 상황 모니터링
# 프로그램이 10개 배치마다 진행 상황을 출력합니다:
# Progress: 1.23% | Tested: 52428800 keys | Speed: 1.45 Mkeys/s | Time: 36.2s
```

## 예제 출력

```
=== AES-128 Single-GPU Bruteforce ===

Plaintext:  00112233445566778899aabbccddeeff
Ciphertext: 8df4e9aac5c7573a27d8d055d6e4d64b
Known key prefix (12 bytes): 2b7e151628aed2a6abf71588

Searching for the last 4 bytes...

GPU Configuration:
  Threads per block: 256
  Blocks: 1024
  Keys per kernel launch: 262144
  Total search space: 2^32 = 4,294,967,296 keys

Starting bruteforce...
Progress: 15.24% | Tested: 654311424 keys | Speed: 1.82 Mkeys/s | Time: 359.5s

=== Results ===
✓ KEY FOUND!
Full key: 2b7e151628aed2a6abf7158809cf4f3c
Keys tested: 156825100
Time elapsed: 86.23 seconds
Average speed: 1.82 Mkeys/s
```

## 보안 고려사항

### 현실적인 공격 시나리오

1. **약한 키 공간**: 일부 바이트가 알려진 경우
2. **Side-channel 공격**: 타이밍, 전력 소비 등
3. **구현 취약점**: 버퍼 오버플로우, 잘못된 난수 생성

### 방어책

- **강력한 키 관리**: 완전한 랜덤 키 생성
- **키 유도 함수 (KDF)**: PBKDF2, bcrypt, scrypt
- **더 강력한 암호**: AES-256
- **추가 보안 계층**: 인증, 무결성 검증 (GCM 모드)

## 참고 자료

- [NIST AES 표준](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.197.pdf)
- [CUDA Programming Guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/)
- [OpenMPI Documentation](https://www.open-mpi.org/doc/)
- 원본 BitSlice AES: [README.md](README.md)

## 라이선스

교육/연구 목적으로만 사용하십시오. 불법적인 목적으로 사용하지 마십시오.
