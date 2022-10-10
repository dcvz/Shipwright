//
//  SAPISpeechSynthesizer.hpp
//  libultraship
//
//  Created by David Chavez on 10.10.22.
//

#ifndef SAPISpeechSynthesizer_hpp
#define SAPISpeechSynthesizer_hpp

#include "SpeechSynthesizer.hpp"
#include <sapi.h>
#include <string>

namespace Ship {
    class SAPISpeechSynthesizer: public SpeechSynthesizer {
    public:
        SAPISpeechSynthesizer() {};

        bool Init(void);
        void Speak(std::string text);
    private:
        ISpVoice * pVoice = NULL;
    };
}

#endif /* SAPISpeechSynthesizer_hpp */