# docker-bake.hcl - Multi-platform builds with GHA cache
# Structure: ./cropper, ./web, ./nginx (pas services/)

group "default" {
  targets = ["gh-runner-aarch64", "balena-storage-aarch64"]
}

variable "REGISTRY" {
  default = "docker.io"
}

variable "REGISTRY_IMAGE" {
  default = "bprtkop"
}

variable "REGISTRY_HUB" {
  default = "gh-runner-rpi-cluster"
}

variable "BAKE_TAG" {
  default = ""
}

variable "GITHUB_SHA" {
  default = ""
}

variable "BALENA_ARCH" {
  default = "aarch64"
}

target "common" {
  
  # GitHub Actions cache (fastest)
  cache-from = ["type=gha"]
  cache-to = ["type=gha,mode=max"]
  
  # Registry configuration
  registry = "${REGISTRY}"
}

# ============================================================================
# RUNNER SERVICE 
# ============================================================================
target "gh-runner" {
  inherits = ["common"]
  
  # Context: ./gh-runner (NOT ./services/cropper/)
  context = "./gh-runner"
  
  args = {
    BUILDKIT_CONTEXT_KEEP_GIT_DIR = 1
  }
  
  # Multi-tag strategy: latest is multiplatform, platform-tagged versions per arch
  tags = [
    "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:latest",
    BAKE_TAG != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${replace(BAKE_TAG, "/", "-")}" : "",
    GITHUB_SHA != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${GITHUB_SHA}" : ""
  ]
  
  # Dynamic dockerfile selection based on BALENA_ARCH
  dockerfile = "Dockerfile.${BALENA_ARCH}"
  
  output = ["type=registry"]
}

# ============================================================================
# BALENA-STORAGE SERVICE
# ============================================================================
target "balena-storage" {
  inherits = ["common"]
  
  # Context: ./balena-storage (NOT ./services/cropper/)
  context = "./balena-storage"
  
  args = {
    BUILDKIT_CONTEXT_KEEP_GIT_DIR = 1
  }
  
  # Multi-tag strategy: latest is multiplatform, platform-tagged versions per arch
  tags = [
    "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:latest",
    BAKE_TAG != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${replace(BAKE_TAG, "/", "-")}" : "",
    GITHUB_SHA != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${GITHUB_SHA}" : ""
  ]
  
  # Dynamic dockerfile selection based on BALENA_ARCH
  dockerfile = "Dockerfile.${BALENA_ARCH}"
  
  output = ["type=registry"]
}

# ============================================================================
# MATRIX BUILDS - Different configurations with platform-specific tags
# ============================================================================

# Build for testing locally (arm/v7 only, for Raspberry Pi)
group "armhf" {
  targets = ["gh-runner-armhf", "balena-storage-armhf"]
}

target "gh-runner-armhf" {
  inherits = ["gh-runner"]
  platforms = ["linux/arm/v7"]
  dockerfile = "Dockerfile.armhf"
  tags = [
    "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:arm32v7",
    BAKE_TAG != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${replace(BAKE_TAG, "/", "-")}-arm32v7" : "",
    GITHUB_SHA != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${GITHUB_SHA}-arm32v7" : ""
  ]
}

target "balena-storage-armhf" {
  inherits = ["balena-storage"]
  platforms = ["linux/arm/v7"]
  dockerfile = "Dockerfile.armhf"
  tags = [
    "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:arm32v7",
    BAKE_TAG != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${replace(BAKE_TAG, "/", "-")}-arm32v7" : "",
    GITHUB_SHA != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${GITHUB_SHA}-arm32v7" : ""
  ]
}

# Build for testing locally (arm64 only, for Raspberry Pi 3-4-5)
group "aarch64" {
  targets = ["gh-runner-aarch64", "balena-storage-aarch64"]
}

target "gh-runner-aarch64" {
  inherits = ["gh-runner"]
  platforms = ["linux/arm/v8"]
  dockerfile = "Dockerfile.aarch64"
  tags = [
    "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:aarch64",
    BAKE_TAG != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${replace(BAKE_TAG, "/", "-")}-aarch64" : "",
    GITHUB_SHA != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${GITHUB_SHA}-aarch64" : ""
  ]
}

target "balena-storage-aarch64" {
  inherits = ["balena-storage"]
  platforms = ["linux/arm/v8"]
  dockerfile = "Dockerfile.aarch64"
  tags = [
    "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:aarch64",
    BAKE_TAG != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${replace(BAKE_TAG, "/", "-")}-aarch64" : "",
    GITHUB_SHA != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${GITHUB_SHA}-aarch64" : ""
  ]
}


# Build for AMD64  (local development)
group "x86_64" {
  targets = ["gh-runner-x86_64", "balena-storage-x86_64"]
}

target "gh-runner-x86_64" {
  inherits = ["gh-runner"]
  platforms = ["linux/amd64"]
  dockerfile = "Dockerfile.x86_64"
  tags = [
    "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:x86_64",
    BAKE_TAG != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${replace(BAKE_TAG, "/", "-")}-x86_64" : "",
    GITHUB_SHA != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${GITHUB_SHA}-x86_64" : ""
  ]
}

target "balena-storage-x86_64" {
  inherits = ["balena-storage"]
  platforms = ["linux/amd4"]
  dockerfile = "Dockerfile.x86_64"
  tags = [
    "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:x86_64",
    BAKE_TAG != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${replace(BAKE_TAG, "/", "-")}-x86_64" : "",
    GITHUB_SHA != "" ? "${REGISTRY}/${REGISTRY_IMAGE}/${REGISTRY_HUB}:${GITHUB_SHA}-x86_64" : ""
  ]
}

