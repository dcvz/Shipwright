#ifdef ENABLE_CROWD_CONTROL

#include "CrowdControl.h"
#include <libultraship/Cvar.h>
#include <libultraship/Console.h>
#include <libultraship/ImGuiImpl.h>
#include <nlohmann/json.hpp>
#include <regex>

extern "C" {
#include <z64.h>
#include "variables.h"
#include "functions.h"
#include "macros.h"
extern GlobalContext* gGlobalCtx;
}

#include "../debugconsole.h"

#define CMD_EXECUTE SohImGui::GetConsole()->Dispatch

void CrowdControl::InitCrowdControl() {
    SDLNet_Init();

    if (SDLNet_ResolveHost(&ip, "127.0.0.1", 43384) == -1) {
        printf("SDLNet_ResolveHost: %s\n", SDLNet_GetError());
    }

    ccThreadReceive = std::thread(&CrowdControl::ReceiveFromCrowdControl, this);
}

void CrowdControl::RunCrowdControl(CCPacket* packet) {
    uint8_t paused = 0;
    uint8_t lastResult = -1;

    while (connected) {
        nlohmann::json dataSend;
        dataSend["id"] = packet->packetId;
        dataSend["type"] = 0;
        dataSend["timeRemaining"] = packet->timeRemaining;

        uint8_t returnSuccess;
        returnSuccess = ExecuteEffect(packet->effectType.c_str(), packet->effectValue);

        if (returnSuccess == EffectResult::Failure) {
            dataSend["status"] = EffectResult::Failure;

            std::string jsonResponse = dataSend.dump();
            SDLNet_TCP_Send(tcpsock, const_cast<char*> (jsonResponse.data()), jsonResponse.size() + 1);
            return;
        }

        if (returnSuccess == EffectResult::Resumed) {
            if (paused && packet->timeRemaining > 0) {
                paused = 0;
                nlohmann::json dataSend;
                dataSend["id"] = packet->packetId;
                dataSend["type"] = 0;
                dataSend["timeRemaining"] = packet->timeRemaining;
                dataSend["status"] = EffectResult::Resumed;

                std::string jsonResponse = dataSend.dump();
                SDLNet_TCP_Send(tcpsock, const_cast<char*> (jsonResponse.data()), jsonResponse.size() + 1);
            }

            if (packet->timeRemaining <= 0) {
                receivedCommands.erase(std::remove(receivedCommands.begin(), receivedCommands.end(), packet), receivedCommands.end());
                RemoveEffect(packet->effectType.c_str());
                return;
            }

            packet->timeRemaining -= 1000;
        } else if (returnSuccess == EffectResult::Paused && paused == 0 && packet->timeRemaining > 0) {
            paused = 1;
            nlohmann::json dataSend;
            dataSend["id"] = packet->packetId;
            dataSend["type"] = 0;
            dataSend["timeRemaining"] = packet->timeRemaining;
            dataSend["status"] = EffectResult::Paused;

            std::string jsonResponse = dataSend.dump();
            SDLNet_TCP_Send(tcpsock, const_cast<char*> (jsonResponse.data()), jsonResponse.size() + 1);
        }

        if (returnSuccess != lastResult && !paused) {
            lastResult = returnSuccess;
            dataSend["status"] = returnSuccess == 1 ? EffectResult::Success : EffectResult::Retry;

            std::string jsonResponse = dataSend.dump();
            SDLNet_TCP_Send(tcpsock, const_cast<char*> (jsonResponse.data()), jsonResponse.size() + 1);
        }
        
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}

void CrowdControl::ReceiveFromCrowdControl()
{
    printf("Waiting for a connection from Crowd Control...");

    while (!connected && CVar_GetS32("gCrowdControl", 0)) {
        tcpsock = SDLNet_TCP_Open(&ip);

        if (tcpsock) {
            connected = true;
            printf("Connected to Crowd Control!");
            break;
        }
    }

    while (connected && CVar_GetS32("gCrowdControl", 0) && tcpsock) {
        int len = SDLNet_TCP_Recv(tcpsock, &received, 512);

        if (!len || !tcpsock || len == -1) {
            printf("SDLNet_TCP_Recv: %s\n", SDLNet_GetError());
            break;
        }

        nlohmann::json dataReceived = nlohmann::json::parse(received);

        CCPacket* packet = new CCPacket();
        packet->packetId = dataReceived["id"];
        auto parameters = dataReceived["parameters"];
        if (parameters.size() > 0) {
            packet->effectValue = dataReceived["parameters"][0];
        }
        packet->effectType = dataReceived["code"].get<std::string>();

        if (strcmp(packet->effectType.c_str(), "high_gravity") == 0 ||
            strcmp(packet->effectType.c_str(), "low_gravity") == 0) {
            packet->effectCategory = "gravity";
            packet->timeRemaining = 30000;
        }
        else if (strcmp(packet->effectType.c_str(), "damage_multiplier") == 0
                    || strcmp(packet->effectType.c_str(), "defense_multiplier") == 0
        ) {
            packet->effectCategory = "defense";
            packet->timeRemaining = 30000;
        }
        else if (strcmp(packet->effectType.c_str(), "giant_link") == 0 ||
            strcmp(packet->effectType.c_str(), "minish_link") == 0 ||
            strcmp(packet->effectType.c_str(), "invisible") == 0 ||
            strcmp(packet->effectType.c_str(), "paper_link") == 0) {
            packet->effectCategory = "link_size";
            packet->timeRemaining = 30000;
        }
        else if (strcmp(packet->effectType.c_str(), "freeze") == 0 ||
            strcmp(packet->effectType.c_str(), "damage") == 0 ||
            strcmp(packet->effectType.c_str(), "heal") == 0 ||
            strcmp(packet->effectType.c_str(), "knockback") == 0 ||
            strcmp(packet->effectType.c_str(), "electrocute") == 0 ||
            strcmp(packet->effectType.c_str(), "burn") == 0 ||
            strcmp(packet->effectType.c_str(), "kill") == 0) {
            packet->effectCategory = "link_damage";
        }
        else if (strcmp(packet->effectType.c_str(), "hover_boots") == 0 ||
            strcmp(packet->effectType.c_str(), "iron_boots") == 0) {
            packet->effectCategory = "boots";
            packet->timeRemaining = 30000;
        }
        else if (strcmp(packet->effectType.c_str(), "add_heart_container") == 0 ||
            strcmp(packet->effectType.c_str(), "remove_heart_container") == 0) {
            packet->effectCategory = "heart_container";
        }
        else if (strcmp(packet->effectType.c_str(), "no_ui") == 0) {
            packet->effectCategory = "ui";
            packet->timeRemaining = 60000;
        }
        else if (strcmp(packet->effectType.c_str(), "fill_magic") == 0 ||
            strcmp(packet->effectType.c_str(), "empty_magic") == 0) {
            packet->effectCategory = "magic";
        }
        else if (strcmp(packet->effectType.c_str(), "ohko") == 0) {
            packet->effectCategory = "ohko";
            packet->timeRemaining = 30000;
        }
        else if (strcmp(packet->effectType.c_str(), "pacifist") == 0) {
            packet->effectCategory = "pacifist";
            packet->timeRemaining = 15000;
        }
        else if (strcmp(packet->effectType.c_str(), "rainstorm") == 0) {
            packet->effectCategory = "weather";
            packet->timeRemaining = 30000;
        }
        else if (strcmp(packet->effectType.c_str(), "reverse") == 0) {
            packet->effectCategory = "controls";
            packet->timeRemaining = 60000;
        }
        else if (strcmp(packet->effectType.c_str(), "add_rupees") == 0
                    || strcmp(packet->effectType.c_str(), "remove_rupees") == 0
        ) {
            packet->effectCategory = "rupees";
        }
        else if (strcmp(packet->effectType.c_str(), "increase_speed") == 0
                    || strcmp(packet->effectType.c_str(), "decrease_speed") == 0
        ) {
            packet->effectCategory = "speed";
            packet->timeRemaining = 30000;
        }
        else if (strcmp(packet->effectType.c_str(), "no_z") == 0) {
            packet->effectCategory = "no_z";
            packet->timeRemaining = 30000;
        }
        else if (strcmp(packet->effectType.c_str(), "spawn_wallmaster") == 0 ||
            strcmp(packet->effectType.c_str(), "spawn_arwing") == 0 ||
            strcmp(packet->effectType.c_str(), "spawn_darklink") == 0 ||
            strcmp(packet->effectType.c_str(), "spawn_stalfos") == 0 ||
            strcmp(packet->effectType.c_str(), "spawn_wolfos") == 0 ||
            strcmp(packet->effectType.c_str(), "spawn_freezard") == 0 ||
            strcmp(packet->effectType.c_str(), "spawn_keese") == 0 ||
            strcmp(packet->effectType.c_str(), "spawn_icekeese") == 0 ||
            strcmp(packet->effectType.c_str(), "spawn_firekeese") == 0 ||
            strcmp(packet->effectType.c_str(), "spawn_tektite") == 0 ||
            strcmp(packet->effectType.c_str(), "spawn_likelike") == 0 ||
            strcmp(packet->effectType.c_str(), "cucco_storm") == 0) {
            packet->effectCategory = "spawn";
        }
        else {
            packet->effectCategory = "none";
            packet->timeRemaining = 0;
        }

        // Check if effect already exists
        uint8_t anotherEffect = 0;

        nlohmann::json dataSend;
        dataSend["id"] = packet->packetId;
        dataSend["type"] = 0;
        dataSend["timeRemaining"] = packet->timeRemaining;

        for (CCPacket* pack : receivedCommands) {
            if (pack != packet && pack->effectCategory == packet->effectCategory && pack->packetId < packet->packetId) {
                anotherEffect = 1;
                dataSend["status"] = EffectResult::Retry;
                break;
            }
        }

        std::string jsonResponse = dataSend.dump();
        SDLNet_TCP_Send(tcpsock, const_cast<char*> (jsonResponse.data()), jsonResponse.size() + 1);

        if (anotherEffect != 1) {
            receivedCommands.push_back(packet);
            std::thread t = std::thread(&CrowdControl::RunCrowdControl, this, packet);
            t.detach();
        }
    }

    if (connected) {
        SDLNet_TCP_Close(tcpsock);
        SDLNet_Quit();
        connected = false;
    }
}

uint8_t CrowdControl::ExecuteEffect(const char* effectId, uint32_t value) {

    // Don't execute effect and don't advance timer when the player is not in a proper loaded savefile
    // and when they're busy dying.
    if (gGlobalCtx == NULL || gGlobalCtx->gameOverCtx.state > 0 || gSaveContext.fileNum < 0 || gSaveContext.fileNum > 2) {
        return EffectResult::Paused;
    }

    Player* player = GET_PLAYER(gGlobalCtx);

    if (player != NULL) {
        if (strcmp(effectId, "add_heart_container") == 0) {
            if (gSaveContext.healthCapacity >= 0x140) {
                return EffectResult::Failure;
            }
            
            CMD_EXECUTE("add_heart_container");
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "remove_heart_container") == 0) {
            if ((gSaveContext.healthCapacity - 0x10) <= 0) {
                return EffectResult::Failure;
            }
            
            CMD_EXECUTE("remove_heart_container");
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "fill_magic") == 0) {
            if (!gSaveContext.magicAcquired) {
                return EffectResult::Failure;
            }

            if (gSaveContext.magic >= (gSaveContext.doubleMagic + 1) + 0x30) {
                return EffectResult::Failure;
            }

            CMD_EXECUTE("fill_magic");
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "empty_magic") == 0) {
            if (!gSaveContext.magicAcquired || gSaveContext.magic <= 0) {
                return EffectResult::Failure;
            }

            CMD_EXECUTE("empty_magic");
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "add_rupees") == 0) {
            CMD_EXECUTE(std::format("update_rupees {}", value));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "remove_rupees") == 0) {
            if (gSaveContext.rupees - value < 0) {
                return EffectResult::Failure;
            }

            CMD_EXECUTE(std::format("update_rupees -{}", value));
            return EffectResult::Resumed;
        }
    }

    if (player != NULL && !Player_InBlockingCsMode(gGlobalCtx, player) && gGlobalCtx->pauseCtx.state == 0
                                                                       && gGlobalCtx->msgCtx.msgMode == 0) {
        if (strcmp(effectId, "high_gravity") == 0) {
            CMD_EXECUTE("gravity 2");
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "low_gravity") == 0) {
            CMD_EXECUTE("gravity 0");
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "kill") == 0
                    || strcmp(effectId, "freeze") == 0
                    || strcmp(effectId, "burn") == 0
                    || strcmp(effectId, "electrocute") == 0
                    || strcmp(effectId, "cucco_storm") == 0
        ) {
            if (PlayerGrounded(player)) {
                CMD_EXECUTE(std::format("{}", effectId));
                return EffectResult::Resumed;
            }
            return EffectResult::Paused;
        } else if (strcmp(effectId, "heal") == 0
                    || strcmp(effectId, "knockback") == 0
        ) {
            CMD_EXECUTE(std::format("{} {}", effectId, value));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "giant_link") == 0
                    || strcmp(effectId, "minish_link") == 0
                    || strcmp(effectId, "no_ui") == 0
                    || strcmp(effectId, "invisible") == 0
                    || strcmp(effectId, "paper_link") == 0
                    || strcmp(effectId, "no_z") == 0
                    || strcmp(effectId, "ohko") == 0
                    || strcmp(effectId, "pacifist") == 0
                    || strcmp(effectId, "rainstorm") == 0
        ) {
            CMD_EXECUTE(std::format("{} 1", effectId));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "reverse") == 0) {
            CMD_EXECUTE("reverse_controls 1"); 
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "iron_boots") == 0) {
            CMD_EXECUTE("boots iron");
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "hover_boots") == 0) {
            CMD_EXECUTE("boots hover");
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "spawn_wallmaster") == 0) {
            CMD_EXECUTE(std::format("spawn 17 {} {} {} {}", 0, player->actor.world.pos.x, player->actor.world.pos.y, player->actor.world.pos.z));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "spawn_arwing") == 0) {
            CMD_EXECUTE(std::format("spawn 315 {} {} {} {}", 1, player->actor.world.pos.x, player->actor.world.pos.y + 100, player->actor.world.pos.z));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "spawn_darklink") == 0) {
            CMD_EXECUTE(std::format("spawn 51 {} {} {} {}", 0, player->actor.world.pos.x + 75, player->actor.world.pos.y + 50, player->actor.world.pos.z));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "spawn_stalfos") == 0) {
            CMD_EXECUTE(std::format("spawn 2 {} {} {} {}", 1, player->actor.world.pos.x + 75, player->actor.world.pos.y, player->actor.world.pos.z));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "spawn_wolfos") == 0) {
            CMD_EXECUTE(std::format("spawn 431 {} {} {} {}", 0, player->actor.world.pos.x + 75, player->actor.world.pos.y + 50, player->actor.world.pos.z));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "spawn_freezard") == 0) {
            CMD_EXECUTE(std::format("spawn 289 {} {} {} {}", 0, player->actor.world.pos.x + 75, player->actor.world.pos.y + 50, player->actor.world.pos.z));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "spawn_keese") == 0) {
            CMD_EXECUTE(std::format("spawn 19 {} {} {} {}", 2, player->actor.world.pos.x + 75, player->actor.world.pos.y + 50, player->actor.world.pos.z));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "spawn_icekeese") == 0) {
            CMD_EXECUTE(std::format("spawn 19 {} {} {} {}", 4, player->actor.world.pos.x + 75, player->actor.world.pos.y + 50, player->actor.world.pos.z));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "spawn_firekeese") == 0) {
            CMD_EXECUTE(std::format("spawn 19 {} {} {} {}", 1, player->actor.world.pos.x + 75, player->actor.world.pos.y + 50, player->actor.world.pos.z));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "spawn_tektite") == 0) {
            CMD_EXECUTE(std::format("spawn 27 {} {} {} {}", 0, player->actor.world.pos.x + 75, player->actor.world.pos.y + 50, player->actor.world.pos.z));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "spawn_likelike") == 0) {
            CMD_EXECUTE(std::format("spawn 221 {} {} {} {}", 0, player->actor.world.pos.x, player->actor.world.pos.y + 200, player->actor.world.pos.z));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "increase_speed") == 0) {
           CMD_EXECUTE("speed_modifier 2");
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "decrease_speed") == 0) {
           CMD_EXECUTE("speed_modifier -2");
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "damage_multiplier") == 0) {
            CMD_EXECUTE(std::format("defense_modifier -{}", value));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "defense_multiplier") == 0) {
            CMD_EXECUTE(std::format("defense_modifier {}", value));
            return EffectResult::Resumed;
        } else if (strcmp(effectId, "damage") == 0) {
            if ((gSaveContext.healthCapacity - 0x10) <= 0) {
                return EffectResult::Failure;
            }
            
            CMD_EXECUTE(std::format("damage {}", effectId, value));
            return EffectResult::Resumed;
        }
    }

    return EffectResult::Paused;
}

void CrowdControl::RemoveEffect(const char* effectId) {
    if (gGlobalCtx == NULL) {
        return;
    }

    Player* player = GET_PLAYER(gGlobalCtx);

    if (player != NULL) {
        if (strcmp(effectId, "giant_link") == 0
                || strcmp(effectId, "minish_link") == 0
                || strcmp(effectId, "no_ui") == 0
                || strcmp(effectId, "invisible") == 0
                || strcmp(effectId, "paper_link") == 0
                || strcmp(effectId, "no_z") == 0
                || strcmp(effectId, "ohko") == 0
                || strcmp(effectId, "pacifist") == 0
                || strcmp(effectId, "rainstorm") == 0
        ) {
            CMD_EXECUTE(std::format("{} 0", effectId));
            return;
        } else if (strcmp(effectId, "iron_boots") == 0 || strcmp(effectId, "hover_boots") == 0) {
            CMD_EXECUTE("boots kokiri");
            return;
        } else if (strcmp(effectId, "high_gravity") == 0 || strcmp(effectId, "low_gravity") == 0) {
            CMD_EXECUTE("gravity 1");
            return;
        } else if (strcmp(effectId, "reverse") == 0) {
            CMD_EXECUTE("reverse_controls 0");
            return;
        } else if (strcmp(effectId, "increase_speed") == 0
                    || strcmp(effectId, "decrease_speed") == 0
        ) {
            CMD_EXECUTE("speed_modifier 0");
            return;
        } else if (strcmp(effectId, "damage_multiplier") == 0
                    || strcmp(effectId, "defense_multiplier") == 0
        ) {
            CMD_EXECUTE("defense_modifier 0");
            return;
        }
    }
}
#endif
