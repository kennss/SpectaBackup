//
//  @file        Infra-Bridging.h
//  @description Bridging header exposing low-level macOS SPIs to Swift that the Darwin module does
//               not surface — notably the APFS fs_snapshot family used for consistent source reads.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

#ifndef INFRA_BRIDGING_H
#define INFRA_BRIDGING_H

#include <sys/snapshot.h>
#include <sys/attr.h>
#include <sys/mount.h>

#endif /* INFRA_BRIDGING_H */
