#pragma once

#ifndef GameInteractor_h
#define GameInteractor_h

#include "GameInteractionEffect.h"
#include "z64.h"

#define MAX_IP_BUFFER_SIZE 256
#define MAX_PORT_BUFFER_SIZE 6

typedef enum {
    /* 0x00 */ GI_LINK_SIZE_NORMAL,
    /* 0x01 */ GI_LINK_SIZE_GIANT,
    /* 0x02 */ GI_LINK_SIZE_MINISH,
    /* 0x03 */ GI_LINK_SIZE_PAPER,
    /* 0x04 */ GI_LINK_SIZE_RESET
} GILinkSize;

typedef enum {
    /* 0x00 */ GI_GRAVITY_LEVEL_LIGHT,
    /* 0x01 */ GI_GRAVITY_LEVEL_NORMAL,
    /* 0x02 */ GI_GRAVITY_LEVEL_HEAVY,
} GIGravityLevel;

#ifdef __cplusplus
extern "C" {
#endif
uint8_t GameInteractor_NoUIActive();
GILinkSize GameInteractor_GetLinkSize();
void GameInteractor_SetLinkSize(GILinkSize size);
uint8_t GameInteractor_InvisibleLinkActive();
uint8_t GameInteractor_OneHitKOActive();
uint8_t GameInteractor_PacifistModeActive();
uint8_t GameInteractor_DisableZTargetingActive();
uint8_t GameInteractor_ReverseControlsActive();
int32_t GameInteractor_DefenseModifier();
int32_t GameInteractor_RunSpeedModifier();
GIGravityLevel GameInteractor_GravityLevel();
#ifdef __cplusplus
}
#endif


#ifdef __cplusplus
#include <thread>
#include <vector>
#include <functional>

#ifdef ENABLE_REMOTE_CONTROL
#include <SDL2/SDL_net.h>
#include <nlohmann/json.hpp>
#endif

#define DEFINE_HOOK(name, type)         \
    struct name {                       \
        typedef std::function<type> fn; \
    }

class GameInteractor {
public:
    static GameInteractor* Instance;

    // Gsme State
    class State {
    public:
        static bool NoUIActive;
        static GILinkSize LinkSize;
        static bool InvisibleLinkActive;
        static bool OneHitKOActive;
        static bool PacifistModeActive;
        static bool DisableZTargetingActive;
        static bool ReverseControlsActive;
        static int32_t DefenseModifier;
        static int32_t RunSpeedModifier;
        static GIGravityLevel GravityLevel;

        static void SetPacifistMode(bool active);
    };

    #ifdef ENABLE_REMOTE_CONTROL
    char remoteIPStr[MAX_IP_BUFFER_SIZE];
    char remotePortStr[MAX_PORT_BUFFER_SIZE];
    bool isRemoteInteractorEnabled;

    void EnableRemoteInteractor();
    void DisableRemoteInteractor();
    void RegisterRemoteForwarder(std::function<void(nlohmann::json)> method);
    void TransmitMessageToRemote(nlohmann::json payload);
    #endif

    // Effects
    static GameInteractionEffectQueryResult CanApplyEffect(GameInteractionEffectBase* effect);
    static GameInteractionEffectQueryResult ApplyEffect(GameInteractionEffectBase* effect);
    static GameInteractionEffectQueryResult RemoveEffect(RemovableGameInteractionEffect* effect);

    // Game Hooks
    template <typename H> struct RegisteredGameHooks { inline static std::vector<typename H::fn> functions; };
    template <typename H> void RegisterGameHook(typename H::fn h) { RegisteredGameHooks<H>::functions.push_back(h); }
    template <typename H, typename... Args> void ExecuteHooks(Args&&... args) {
        for (auto& fn : RegisteredGameHooks<H>::functions) {
            fn(std::forward<Args>(args)...);
        }
    }

    DEFINE_HOOK(OnReceiveItem, void(u8 item));
    DEFINE_HOOK(OnSceneInit, void(s16 sceneNum));
    
    
    DEFINE_HOOK(OnSaveFile, void(int fileNum));
    DEFINE_HOOK(OnLoadFile, void(int fileNum));
    DEFINE_HOOK(OnDeleteFile, void(int fileNum));

    // Helpers
    static bool IsSaveLoaded();
    static bool IsGameplayPaused();
    static bool CanSpawnEnemy();

    class RawAction {
    public:
        static void AddOrRemoveHealthContainers(int16_t amount);
        static void AddOrRemoveMagic(int8_t amount);
        static void HealOrDamagePlayer(int16_t hearts);
        static void SetPlayerHealth(int16_t hearts);
        static void SetLinkInvisibility(bool active);
        static void SetWeatherStorm(bool active);
        static void ForceEquipBoots(int8_t boots);
        static void FreezePlayer();
        static void BurnPlayer();
        static void ElectrocutePlayer();
        static void KnockbackPlayer(float strength);
        static void GiveDekuShield();
        static void SpawnCuccoStorm();
        static void ForceInterfaceUpdate();

        static GameInteractionEffectQueryResult SpawnEnemyWithOffset(uint32_t enemyId, int32_t enemyParams);
    };
private:
#ifdef ENABLE_REMOTE_CONTROL
    IPaddress remoteIP;
    TCPsocket remoteSocket;
    std::thread remoteThreadReceive;
    bool isRemoteInteractorConnected;
    std::function<void(nlohmann::json)> remoteForwarder;

    void ReceiveFromServer();
    void HandleRemoteMessage(char message[512]);
#endif
};

#endif /* __cplusplus */
#endif /* GameInteractor_h */
