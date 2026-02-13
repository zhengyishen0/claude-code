# Architecture Comparison

## Overview

Running WeChat on Mac requires an Android environment. This document compares the available options.

## Options

### 1. AVD (Android Virtual Device)

```
Mac → Hypervisor.framework → QEMU → Android → WeChat
```

**Pros:**
- Native Mac support
- Snapshot support (~5s resume)
- GPU acceleration (Metal)
- Lower CPU/heat when idle

**Cons:**
- Heavier install (~6GB)
- Requires Android SDK

### 2. Lima + Redroid

```
Mac → Virtualization.framework → Lima VM → Docker → Redroid → WeChat
```

**Pros:**
- Container-based (reproducible)
- Smaller Redroid image (~2.5GB)
- Good for automation

**Cons:**
- No snapshot support
- Higher CPU/heat (nested virtualization)
- Complex setup (binder modules)

### 3. UTM + Ubuntu + Redroid

```
Mac → QEMU → Ubuntu VM → Docker → Redroid → WeChat
```

**Pros:**
- Snapshot support via `utmctl suspend`
- Full control over VM

**Cons:**
- Complex setup
- Large disk footprint (~8GB)
- Slowest boot time

### 4. Native Linux Server

```
Linux → Docker → Redroid → WeChat
```

**Pros:**
- Simplest setup
- Always on (no boot time)
- Lowest resource usage

**Cons:**
- Requires Linux server
- Data not local

## Comparison Table

| Feature | AVD | Lima+Redroid | UTM | Linux Server |
|---------|-----|--------------|-----|--------------|
| Snapshot | Yes | No | Yes | N/A (always on) |
| Resume time | ~5s | ~40s boot | ~5s | 0s |
| RAM usage | ~3GB | ~6GB | ~6GB | ~2GB |
| CPU (idle) | Low | High | Medium | Low |
| Setup | Easy | Medium | Hard | Easy |
| Mac native | Yes | Yes | Yes | No |

## Redroid Tablet Mode

WeChat requires specific device properties for tablet login (phone+tablet simultaneous):

```bash
ro.build.characteristics=tablet
ro.product.brand=google
ro.product.manufacturer=Google
ro.product.model=Pixel Tablet
ro.product.device=tangorpro
```

Without these, WeChat only offers "tablet only" login (replaces phone).

## Resource Requirements

### Minimum
- RAM: 8GB system (2-3GB for emulator)
- Disk: 10GB free
- CPU: Apple Silicon M1+

### Recommended
- RAM: 16GB system
- Disk: 20GB free
- CPU: M2+ for smoother experience

## Kernel Modules (Redroid)

Redroid requires Linux kernel binder support:

```bash
# Load binder module
sudo modprobe binder_linux

# Mount binderfs
sudo mkdir -p /dev/binderfs
sudo mount -t binder binder /dev/binderfs
```

This is why Redroid can't run directly on Mac - macOS lacks these kernel features.
Lima provides a Linux VM where these modules can be loaded.
