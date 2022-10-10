//
//  SAPISpeechSynthesizer.cpp
//  libultraship
//
//  Created by David Chavez on 10.10.22.
//

#include "SAPISpeechSynthesizer.hpp"
#include <thread>

namespace Ship {
    bool SAPISpeechSynthesizer::Init() {
        CoInitialize(NULL, COINIT_MULTITHREADED);
        CoCreateInstance(CLSID_SpVoice, NULL, CLSCTX_ALL, IID_ISpVoice, (void **)&pVoice);        
    }

    void AVSpeechSynthesizer::SpeakThreadTask(const std::string &text) {
        const int w = 512;
        int* wp = const_cast <int*> (&w);
        *wp = strlen(text.c_str());

        wchar_t wtext[w];
        mbstowcs(wtext, text.c_str(), strlen(text.c_str()) + 1);

        pVoice->Speak(wtext, SPF_IS_XML | SPF_ASYNC | SPF_PURGEBEFORESPEAK, NULL);
    }

    void AVSpeechSynthesizer::Speak(std::string text) {
        if (text == nullptr) {
            return;
        }
        std::thread t1(SpeakThreadTask, text);
        t1.detach();
    }
}
