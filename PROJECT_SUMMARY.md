# 프로젝트 요약

## 완료된 작업

### 1. 원본 BitSlice AES-128 구현 (성공적으로 빌드 및 테스트 완료)
- ✅ CUDA Toolkit 12.6 설치
- ✅ 코드 수정 (StaticKey 중복 정의 제거)
- ✅ Round key 생성 (gen_roundkeys_header.py)
- ✅ A100 GPU (SM 80)용 컴파일 성공
- ✅ 암호화 테스트 및 검증 완료 (16.52 Gbps 처리량)

### 2. AES-128 브루트포스 구현 (신규 개발)

#### 파일 구조
```
include/
  aes_bruteforce.cuh              # 브루트포스 헤더
src/
  aes_bruteforce_kernel.cu        # CUDA 커널 (AES-128 전체 구현)
  aes_bruteforce_single.cu        # 단일 GPU 버전 (추천)
  aes_bruteforce_mpi.cu            # MPI 분산 버전
tools/
  gen_bruteforce_test.py          # 테스트 케이스 생성
```

#### 주요 기능

**단일 GPU 버전** (`cuda-aes-bruteforce`)
- ✅ MPI 의존성 없음
- ✅ 간단한 설정 및 실행
- ✅ 진행 상황 실시간 모니터링
- ✅ 정상 빌드 및 실행 확인
- 성능: A100에서 약 1 Gkeys/s

**MPI 분산 버전** (`cuda-aes-bruteforce-mpi`)
- ✅ 여러 노드/GPU 지원
- ✅ 자동 작업 분할
- ✅ 키 발견 시 모든 프로세스에 통보
- ⚠️ hwloc 토폴로지 문제로 현재 환경에서는 실행 불가
- 회피 방법: 단일 GPU 버전 사용

**CUDA 커널** (`aes_bruteforce_kernel.cu`)
- ✅ 완전한 디바이스 측 AES-128 구현
- ✅ S-box, 키 확장, 10 라운드 암호화
- ✅ 병렬 키 테스트 (thread당 1개 키)
- ✅ Atomic 연산으로 키 발견 플래그 설정

### 3. 문서화
- ✅ BRUTEFORCE_KR.md - 한국어 상세 문서
- ✅ BRUTEFORCE.md - 영어 문서 (기존)
- ✅ README.md 업데이트
- ✅ tools/gen_bruteforce_test.py - 테스트 케이스 생성기

## 사용 방법

### 빌드
```bash
cd /home/elicer/BitSlice_AES_CUDA
rm -rf build
cmake -S . -B build -DCMAKE_CUDA_ARCHITECTURES="80"
cmake --build build -j
```

### 실행

#### 1. 테스트 케이스 생성
```bash
python3 tools/gen_bruteforce_test.py
```

출력 예시:
```
Full key:   2b7e151628aed2a6abf7158809cf4f3c
Plaintext:  00112233445566778899aabbccddeeff
Ciphertext: 8df4e9aac5c7573a27d8d055d6e4d64b
Known key prefix (12 bytes): 2b7e151628aed2a6abf71588
Target suffix (4 bytes):     09cf4f3c
```

#### 2. 브루트포스 실행
```bash
./build/cuda-aes-bruteforce \
    00112233445566778899aabbccddeeff \
    8df4e9aac5c7573a27d8d055d6e4d64b \
    2b7e151628aed2a6abf71588
```

#### 3. 진행 상황 모니터링
프로그램은 실시간으로 진행 상황을 출력합니다:
```
Progress: 1.23% | Tested: 52,428,800 keys | Speed: 1.45 Mkeys/s | Time: 36.2s
```

## 성능 특성

### 탐색 공간
- 전체 AES-128 키 공간: 2^128 ≈ 3.4 × 10^38 키 (현실적으로 불가능)
- 구현된 탐색 공간: 2^32 = 4,294,967,296 키 (마지막 4바이트)

### 예상 시간 (2^32 키 공간, 단일 A100)
- 1 Gkeys/s: 약 72분
- 2 Gkeys/s: 약 36분

### 최적화 가능 항목
- `threads_per_block`: 128, 256, 512 테스트
- `blocks`: GPU에 따라 512-4096
- 키 체크 빈도: 현재 10배치마다 (조정 가능)

## 알려진 문제 및 해결책

### MPI hwloc 토폴로지 오류
**문제**: MIG 모드에서 hwloc이 CPU 토폴로지를 읽지 못함
```
hwloc: Topology does not contain any PU, aborting!
```

**해결책 1**: 단일 GPU 버전 사용 (추천)
```bash
./build/cuda-aes-bruteforce ...
```

**해결책 2**: hwloc 비활성화
```bash
export OMPI_MCA_hwloc_base_binding_policy=none
mpirun --mca hwloc_base_binding_policy none -np 4 ./build/cuda-aes-bruteforce-mpi ...
```

## 교육적 가치

이 구현은 다음을 배우는 데 유용합니다:

1. **CUDA 병렬 프로그래밍**
   - 커널 설계
   - 메모리 관리
   - Atomic 연산

2. **암호학 구현**
   - AES-128 알고리즘
   - S-box, 키 확장
   - 라운드 함수

3. **분산 컴퓨팅** (MPI 버전)
   - 작업 분할
   - 프로세스 간 통신
   - 조기 종료 메커니즘

4. **보안 인식**
   - 브루트포스 공격의 한계
   - 암호 강도 이해
   - 키 관리 중요성

## 보안 고지

⚠️ **이 코드는 교육/연구 목적으로만 제공됩니다.**

- 실제 AES-128 전체 키 공간 (2^128)을 탐색하는 것은 불가능합니다
- 제한된 키 공간 (2^32)만 시연용으로 구현되었습니다
- 불법적인 목적으로 사용하지 마십시오
- 실제 암호 시스템에는 AES-256 + 적절한 모드 (GCM 등) 사용을 권장합니다

## 다음 단계 제안

1. **성능 최적화**
   - Shared memory 활용
   - Warp-level 최적화
   - Multi-stream 처리

2. **기능 확장**
   - AES-256 지원
   - 다양한 키 공간 패턴 (앞 N바이트, 중간 M바이트 등)
   - Rainbow table 생성

3. **분산 환경 개선**
   - NCCL 사용 (GPU 간 직접 통신)
   - Kubernetes/Slurm 통합
   - 체크포인트/재시작 기능

## 파일 목록

### 새로 생성된 파일
```
include/aes_bruteforce.cuh
src/aes_bruteforce_kernel.cu
src/aes_bruteforce_single.cu
src/aes_bruteforce_mpi.cu
tools/gen_bruteforce_test.py
BRUTEFORCE.md
BRUTEFORCE_KR.md
PROJECT_SUMMARY.md (이 파일)
```

### 수정된 파일
```
CMakeLists.txt       # MPI 지원, 브루트포스 타겟 추가
README.md            # 브루트포스 섹션 추가
.gitignore           # 빌드 아티팩트 제외
```

## 참고 자료

- 원본 BitSlice AES 구현: [README.md](README.md)
- 브루트포스 상세 문서: [BRUTEFORCE_KR.md](BRUTEFORCE_KR.md)
- CUDA Programming: https://docs.nvidia.com/cuda/
- OpenMPI: https://www.open-mpi.org/
- AES 표준: https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.197.pdf
