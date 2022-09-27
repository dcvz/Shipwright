#pragma once

#include "stdint.h"

#define PAPER_LINK_DISABLED 0
#define PAPER_LINK_X_AXIS 1
#define PAPER_LINK_Z_AXIS 2

#define GRAVITY_LEVEL_NORMAL 1.0f
#define GRAVITY_LEVEL_LIGHT 0.0f
#define GRAVITY_LEVEL_HEAVY 2.0f

#ifdef __cplusplus
extern "C" {
#endif
extern bool noUI;
extern bool giantLink;
extern bool minishLink;
extern uint32_t paperLink;
extern uint32_t gravityLevel;
extern bool resetLinkScale;
extern bool invisibleLink;
extern bool oneHitKO;
extern bool pacifistMode;
extern int32_t defenseModifier;
extern bool noZ;
extern bool reverseControls;
extern int32_t speedModifier;
#ifdef __cplusplus
}
#endif

void DebugConsole_Init(void);
