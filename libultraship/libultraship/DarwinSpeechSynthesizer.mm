//
//  DarwinSpeechSynthesizer.mm
//  libultraship
//
//  Created by David Chavez on 10.10.22.
//

#include "DarwinSpeechSynthesizer.h"
#import <AVFoundation/AVFoundation.h>

namespace Ship {
    bool DarwinSpeechSynthesizer::Init() {
        synthesizer = [[AVSpeechSynthesizer alloc] init];
    }

    void DarwinSpeechSynthesizer::Speak(std::string text) {
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@(text.c_str())];
        [(AVSpeechSynthesizer *)synthesizer speakUtterance:utterance];
    }
}
