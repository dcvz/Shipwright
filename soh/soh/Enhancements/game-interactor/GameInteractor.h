#pragma once

#ifndef GameInteractor_h
#define GameInteractor_h

#include "GameInteractionEffect.h"
#include "z64.h"

enum {
    GI_LINK_SIZE_NORMAL,
    GI_LINK_SIZE_GIANT,
    GI_LINK_SIZE_MINISH,
    GI_LINK_SIZE_PAPER
};

#ifdef __cplusplus

#include <vector>

#define DEFINE_HOOK(name, type)         \
    struct name {                       \
        typedef std::function<type> fn; \
    }

extern "C" void GameInteractor_ExecuteOnReceiveItemHooks(PlayState* play, u8 item);

class GameInteractor {
public:
    static GameInteractor* Instance;

    // Effects
    static GameInteractionEffectQueryResult CanApplyEffect(GameInteractionEffectBase* effect);
    static GameInteractionEffectQueryResult ApplyEffect(GameInteractionEffectBase* effect);
    static GameInteractionEffectQueryResult RemoveEffect(GameInteractionEffectBase* effect);

    // Game Hooks
    template <typename H> struct RegisteredGameHooks { inline static std::vector<typename H::fn> functions; };
    template <typename H> void RegisterGameHook(typename H::fn h) { RegisteredGameHooks<H>::functions.push_back(h); }
    template <typename H, typename... Args> void ExecuteHooks(Args&&... args) {
        for (auto& fn : RegisteredGameHooks<H>::functions) {
            fn(std::forward<Args>(args)...);
        }
    }

    DEFINE_HOOK(OnReceiveItem, void(PlayState* play, u8 item));

    // Helpers
    static bool IsSaveLoaded();
    static bool IsGameplayPaused();
    static bool CanSpawnEnemy();

    class RawAction {
    public:
        static void AddOrRemoveHealthContainers(int32_t amount);
        static void AddOrRemoveMagic(int32_t amount);
        static void HealOrDamagePlayer(int32_t hearts);
        static void SetPlayerHealth(uint32_t hearts);
        static void SetLinkSize(uint8_t size);
        static void SetLinkInvisibility(uint8_t effectState);
        static void SetPacifistMode(uint8_t effectState);
        static void SetWeatherStorm(uint8_t effectState);
        static void ForceEquipBoots(uint8_t boots);
        static void FreezePlayer();
        static void BurnPlayer();
        static void ElectrocutePlayer();
        static void KnockbackPlayer(uint8_t strength);
        static void GiveDekuShield();
        static void SpawnCuccoStorm();

        static GameInteractionEffectQueryResult SpawnEnemyWithOffset(uint32_t enemyId, int32_t enemyParams);
    };
};

#endif /* __cplusplus */
#endif /* GameInteractor_h */
