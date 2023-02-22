#ifdef ENABLE_REMOTE_CONTROL

#include "GameInteractor.h"
#include <spdlog/spdlog.h>
#include <ImGui/imgui.h>
#include <ImGui/imgui_internal.h>
#include <unordered_map>
#include <tuple>

// MARK: - Declarations

/// Map of string name to enum value and flag whether it takes in a param or not
std::unordered_map<std::string, std::tuple<GameInteractionEffect::Values, bool>> nameToEnum = {
    { "modify_heart_container", { GameInteractionEffect::Values::modifyHeartContainers, true }},
    { "fill_magic", { GameInteractionEffect::Values::fillMagic, false }},
    { "empty_magic", { GameInteractionEffect::Values::emptyMagic, false }},
    { "modify_rupees", { GameInteractionEffect::Values::modifyRupees, true }},
    { "no_ui", { GameInteractionEffect::Values::noUI, false }},
    { "modify_gravity", { GameInteractionEffect::Values::modifyGravity, true }},
    { "modify_health", { GameInteractionEffect::Values::modifyHealth, true }},
    { "set_player_health", { GameInteractionEffect::Values::setPlayerHealth, true }},
    { "freeze_player", { GameInteractionEffect::Values::freezePlayer, false }},
    { "burn_player", { GameInteractionEffect::Values::burnPlayer, false }},
    { "electrocute_player", { GameInteractionEffect::Values::electrocutePlayer, false }},
    { "knockback_player", { GameInteractionEffect::Values::knockbackPlayer, true }},
    { "modify_link_size", { GameInteractionEffect::Values::modifyLinkSize, true }},
    { "invisible_link", { GameInteractionEffect::Values::invisibleLink, false }},
    { "pacifist_mode", { GameInteractionEffect::Values::pacifistMode, false }},
    { "disable_z_targeting", { GameInteractionEffect::Values::disableZTargeting, false }},
    { "weather_rainstorm", { GameInteractionEffect::Values::weatherRainstorm, false }},
    { "reverse_controls", { GameInteractionEffect::Values::reverseControls, false }},
    { "force_equip_boots", { GameInteractionEffect::Values::forceEquipBoots, true }},
    { "modify_run_speed_modifier", { GameInteractionEffect::Values::modifyRunSpeedModifier, true }},
    { "one_hit_ko", { GameInteractionEffect::Values::oneHitKO, false }},
    { "modify_defense_modifier", { GameInteractionEffect::Values::modifyDefenseModifier, true }},
    { "give_deku_shield", { GameInteractionEffect::Values::giveDekuShield, false }},
    { "spawn_cucco_storm", { GameInteractionEffect::Values::spawnCuccoStorm, false }}
};

// MARK: - Remote

void GameInteractor::EnableRemoteInteractor() {
    if (isRemoteInteractorEnabled) {
        return;
    }

    Uint16 port;
    ImGui::DataTypeApplyFromText(GameInteractor::Instance->remotePortStr, ImGuiDataType_U16, &port, "%u");

    if (SDLNet_ResolveHost(&remoteIP, remoteIPStr, port) == -1) {
        SPDLOG_ERROR("[GameInteractor] SDLNet_ResolveHost: {}", SDLNet_GetError());
    }

    isRemoteInteractorEnabled = true;
    remoteThreadReceive = std::thread(&GameInteractor::ReceiveFromServer, this);
}

void GameInteractor::RegisterRemoteForwarder(std::function<void(nlohmann::json)> method) {
    remoteForwarder = method;
}

void GameInteractor::DisableRemoteInteractor() {
    if (!isRemoteInteractorEnabled) {
        return;
    }

    isRemoteInteractorEnabled = false;
    remoteThreadReceive.join();
    remoteForwarder = nullptr;
}

void GameInteractor::TransmitMessageToRemote(nlohmann::json payload) {
    std::string jsonPayload = payload.dump();
    SDLNet_TCP_Send(remoteSocket, jsonPayload.c_str(), jsonPayload.size());
}

// MARK: - Private

void GameInteractor::ReceiveFromServer() {
    while (isRemoteInteractorEnabled) {
        while (!isRemoteInteractorConnected && isRemoteInteractorEnabled) {
            SPDLOG_TRACE("[GameInteractor] Attempting to make connection to server...");
            remoteSocket = SDLNet_TCP_Open(&remoteIP);

            if (remoteSocket) {
                isRemoteInteractorConnected = true;
                SPDLOG_TRACE("[GameInteractor] Connection to server established!");
                
                // transmit supported events to remote
                nlohmann::json payload;
                payload["action"] = "identify";
                payload["supported_events"] = nlohmann::json::array();
                for (auto& [key, value] : nameToEnum) {
                    nlohmann::json entry;
                    entry["event"] = key;
                    entry["takes_param"] = std::get<1>(value);
                    payload["supported_events"].push_back(entry);
                }
                TransmitMessageToRemote(payload);
                
                break;
            }
        }

        SDLNet_SocketSet socketSet = SDLNet_AllocSocketSet(1);
        if (remoteSocket) {
            SDLNet_TCP_AddSocket(socketSet, remoteSocket);
        }

        // Listen to socket messages
        while (isRemoteInteractorConnected && remoteSocket && isRemoteInteractorEnabled) {
            // we check first if socket has data, to not block in the TCP_Recv
            int socketsReady = SDLNet_CheckSockets(socketSet, 0);

            if (socketsReady == -1) {
                SPDLOG_ERROR("[GameInteractor] SDLNet_CheckSockets: {}", SDLNet_GetError());
                break;
            }

            if (socketsReady == 0) {
                continue;
            }

            char remoteDataReceived[512];
            memset(remoteDataReceived, 0, sizeof(remoteDataReceived));
            int len = SDLNet_TCP_Recv(remoteSocket, &remoteDataReceived, sizeof(remoteDataReceived));
            if (!len || !remoteSocket || len == -1) {
                SPDLOG_ERROR("[GameInteractor] SDLNet_TCP_Recv: {}", SDLNet_GetError());
                break;
            }

            HandleRemoteMessage(remoteDataReceived);
        }

        if (isRemoteInteractorConnected) {
            SDLNet_TCP_Close(remoteSocket);
            isRemoteInteractorConnected = false;
            SPDLOG_TRACE("[GameInteractor] Ending receiving thread...");
        }
    }
}

// making it available as it's defined below
GameInteractionEffectBase* EffectFromJson(std::string name, nlohmann::json payload);

void GameInteractor::HandleRemoteMessage(char message[512]) {
    nlohmann::json payload = nlohmann::json::parse(message);

    if (remoteForwarder) {
        remoteForwarder(payload);
        return;
    }

    // { action: "apply_effect, effect: { "name: "value", "payload": { "parameter": "value" } }
    // { action: "remove_effect, effect: { "name: "value" }
    // if action contains effect then it's an effect
    if (payload["action"] == "apply_effect" || payload["action"] == "remove_effect") {
        nlohmann::json effect = payload["effect"];
        GameInteractionEffectBase* giEffect = EffectFromJson(effect["name"].get<std::string>(), effect["payload"]);
        if (giEffect) {
            if (payload["action"] == "apply_effect") {
                giEffect->Apply();
            } else {
                giEffect->Remove();
            }
        }
    }
}

// MARK: - Effect Helpers

GameInteractionEffectBase* EffectFromJson(std::string name, nlohmann::json payload) {
    if (nameToEnum.find(name) == nameToEnum.end()) {
        return nullptr;
    }

    switch (std::get<0>(nameToEnum[name])) {
        case GameInteractionEffect::Values::modifyHeartContainers: {
            auto effect = new GameInteractionEffect::ModifyHeartContainers();
            effect->parameter = payload["parameter"].get<int32_t>();
            return effect;
        }
        case GameInteractionEffect::Values::fillMagic:
            return new GameInteractionEffect::FillMagic();
        case GameInteractionEffect::Values::emptyMagic:
            return new GameInteractionEffect::EmptyMagic();
        case GameInteractionEffect::Values::modifyRupees: {
            auto effect = new GameInteractionEffect::ModifyRupees();
            effect->parameter = payload["parameter"].get<int32_t>();
            return effect;
        }
        case GameInteractionEffect::Values::noUI:
            return new GameInteractionEffect::NoUI();
        case GameInteractionEffect::Values::modifyGravity: {
            auto effect = new GameInteractionEffect::ModifyGravity();
            effect->parameter = payload["parameter"].get<int32_t>();
            return effect;
        }
        case GameInteractionEffect::Values::modifyHealth: {
            auto effect = new GameInteractionEffect::ModifyHealth();
            effect->parameter = payload["parameter"].get<int32_t>();
            return effect;
        }
        case GameInteractionEffect::Values::setPlayerHealth: {
            auto effect = new GameInteractionEffect::SetPlayerHealth();
            effect->parameter = payload["parameter"].get<int32_t>();
            return effect;
        }
        case GameInteractionEffect::Values::freezePlayer:
            return new GameInteractionEffect::FreezePlayer();
        case GameInteractionEffect::Values::burnPlayer:
            return new GameInteractionEffect::BurnPlayer();
        case GameInteractionEffect::Values::electrocutePlayer:
            return new GameInteractionEffect::ElectrocutePlayer();
        case GameInteractionEffect::Values::knockbackPlayer: {
            auto effect = new GameInteractionEffect::KnockbackPlayer();
            effect->parameter = payload["parameter"].get<int32_t>();
            return effect;
        }
        case GameInteractionEffect::Values::modifyLinkSize: {
            auto effect = new GameInteractionEffect::ModifyLinkSize();
            effect->parameter = payload["parameter"].get<int32_t>();
            return effect;
        }
        case GameInteractionEffect::Values::invisibleLink:
            return new GameInteractionEffect::InvisibleLink();
        case GameInteractionEffect::Values::pacifistMode:
            return new GameInteractionEffect::PacifistMode();
        case GameInteractionEffect::Values::disableZTargeting:
            return new GameInteractionEffect::DisableZTargeting();
        case GameInteractionEffect::Values::weatherRainstorm:
            return new GameInteractionEffect::WeatherRainstorm();
        case GameInteractionEffect::Values::reverseControls:
            return new GameInteractionEffect::ReverseControls();
        case GameInteractionEffect::Values::forceEquipBoots: {
            auto effect = new GameInteractionEffect::ForceEquipBoots();
            effect->parameter = payload["parameter"].get<int32_t>();
            return effect;
        }
        case GameInteractionEffect::Values::modifyRunSpeedModifier: {
            auto effect = new GameInteractionEffect::ModifyRunSpeedModifier();
            effect->parameter = payload["parameter"].get<int32_t>();
            return effect;
        }
        case GameInteractionEffect::Values::oneHitKO:
            return new GameInteractionEffect::OneHitKO();
        case GameInteractionEffect::Values::modifyDefenseModifier: {
            auto effect = new GameInteractionEffect::ModifyDefenseModifier();
            effect->parameter = payload["parameter"].get<int32_t>();
            return effect;
        }
        case GameInteractionEffect::Values::giveDekuShield:
            return new GameInteractionEffect::GiveDekuShield();
        case GameInteractionEffect::Values::spawnCuccoStorm:
            return new GameInteractionEffect::SpawnCuccoStorm();
        default:
            return nullptr;
    }
}

#endif
