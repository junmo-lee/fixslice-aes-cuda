# AES-128 Bruteforce with MPI + CUDA

MPI를 사용한 분산 AES 브루트포스 프로그램입니다.

## 특징

- **MPI 기반 분산 처리**: 여러 노드에서 병렬로 키 탐색
- **CUDA GPU 가속**: 각 노드의 GPU를 활용한 대량 병렬 처리
- **효율적인 키 공간 분할**: 각 MPI 프로세스가 키 공간을 균등 분할
- **실시간 진행 상황 표시**: 5초마다 진행률 및 처리 속도 출력
- **조기 종료**: 한 프로세스가 키를 찾으면 모든 프로세스 즉시 종료

## 빌드

### 사전 요구사항

```bash
# MPI 설치
sudo apt-get install -y openmpi-bin openmpi-common libopenmpi-dev

# CUDA Toolkit (이미 설치되어 있음)
```

### 컴파일

```bash
# MPI 포함하여 빌드
rm -rf build
cmake -S . -B build -DCMAKE_CUDA_ARCHITECTURES="80"
cmake --build build -j
```

## 사용법

### 기본 실행

```bash
mpirun -np <프로세스수> ./build/cuda-aes-bruteforce-mpi \
  <plaintext_hex> <ciphertext_hex> <key_prefix_24chars>
```

### 예제: 4개 프로세스로 실행

```bash
mpirun -np 4 ./build/cuda-aes-bruteforce-mpi \
  00112233445566778899aabbccddeeff \
  69c4e0d86a7b0430d8cdb78070b4c55a \
  2b7e151628aed2a6abf71588
```

또는 제공된 스크립트 사용:

```bash
./run_bruteforce_test.sh
```

## 동작 원리

### 1. 키 공간 분할

- 전체 탐색 공간: 2^32 = 4,294,967,296 개의 키
- 키의 앞 12바이트는 알고 있다고 가정
- 마지막 4바이트(32비트)만 브루트포스
- 각 MPI 프로세스가 키 공간을 균등 분할하여 탐색

### 2. GPU 병렬 처리

- 각 프로세스는 할당된 GPU 사용 (rank % GPU 개수)
- CUDA 커널이 수천 개의 키를 병렬로 테스트
- 배치 단위로 처리하여 진행 상황 확인 가능

### 3. 분산 통신

- MPI를 통해 프로세스 간 통신
- 키를 찾으면 MPI_Bcast로 모든 프로세스에 즉시 알림
- 주기적으로 다른 프로세스의 상태 확인 (MPI_Iprobe)

## 성능

### 단일 노드 (A100 GPU 1개)

- 약 1-2 Gkeys/s (기가키/초)
- 32비트 공간 전체 탐색: 약 4-8초

### 다중 노드 (4 노드, 각 A100 GPU)

- 약 4-8 Gkeys/s
- 32비트 공간 전체 탐색: 약 1-2초
- 거의 선형적인 확장성

## 출력 예시

```
=== AES-128 Bruteforce (MPI + CUDA) ===
MPI Processes: 4
Plaintext:  00112233445566778899aabbccddeeff
Ciphertext: 69c4e0d86a7b0430d8cdb78070b4c55a
Key prefix: 2b7e151628aed2a6abf71588
Searching:  ????????
Search space: 2^32 = 4,294,967,296 keys
Keys per process: 1,073,741,824

[Rank 0] Using GPU 0: NVIDIA A100 (SM 8.0)
[Rank 1] Using GPU 0: NVIDIA A100 (SM 8.0)
[Rank 2] Using GPU 0: NVIDIA A100 (SM 8.0)
[Rank 3] Using GPU 0: NVIDIA A100 (SM 8.0)

[Rank 0] Key range: 0x00000000 to 0x3fffffff (1073741824 keys)
[Rank 1] Key range: 0x40000000 to 0x7fffffff (1073741824 keys)
[Rank 2] Key range: 0x80000000 to 0xbfffffff (1073741824 keys)
[Rank 3] Key range: 0xc0000000 to 0xffffffff (1073741824 keys)

[Rank 0] Progress: 4.66% (50000000/1073741824 keys, 2156.45 Mkeys/s, 23.2s elapsed)
...

[Rank 0] *** KEY FOUND! ***
[Rank 0] Key: 2b7e151628aed2a6abf7158809cf4f3c

=== Results ===
Status: KEY FOUND!
Key: 2b7e151628aed2a6abf7158809cf4f3c

Statistics:
  Total time: 0.52 seconds
  Total keys tested: 168034304 (3.91%)
  Overall throughput: 323.14 Mkeys/s
  Per-process throughput: 80.79 Mkeys/s
```

## 다중 노드 실행

### 호스트 파일 작성

```bash
# hostfile.txt
node1 slots=4
node2 slots=4
node3 slots=4
node4 slots=4
```

### MPI 실행

```bash
mpirun -np 16 --hostfile hostfile.txt \
  --mca btl_tcp_if_include eth0 \
  ./build/cuda-aes-bruteforce-mpi \
  00112233445566778899aabbccddeeff \
  69c4e0d86a7b0430d8cdb78070b4c55a \
  2b7e151628aed2a6abf71588
```

## 주의사항

- **실제 AES-128 브루트포스는 불가능**: 전체 128비트 키 공간(2^128)은 현재 기술로 불가능
- **교육 목적**: 이 프로그램은 MPI + CUDA 분산 처리를 보여주기 위한 예제
- **제한된 탐색 공간**: 마지막 32비트(4바이트)만 탐색하도록 설계
- **GPU 메모리**: 각 노드에 CUDA 지원 GPU 필요

## 확장 가능성

- 더 큰 탐색 공간을 위해 64비트로 확장 가능
- 다른 블록 암호 알고리즘에 적용 가능
- 더 효율적인 키 공간 탐색 전략 추가 가능 (예: 딕셔너리 공격)

## 관련 파일

- `src/aes_bruteforce_mpi.cu` - MPI + CUDA 메인 프로그램
- `src/aes_bruteforce_kernel.cu` - CUDA 브루트포스 커널
- `include/aes_bruteforce.cuh` - 헤더 파일
- `run_bruteforce_test.sh` - 테스트 스크립트
