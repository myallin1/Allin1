package com.njtech.allin1

import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService

// The system calls onNewSession() each time the assistant is invoked
// (power-button long-press, home-swipe, or whatever gesture the device
// maps to "assist") — including from the lock screen, which is the
// whole point of this registration over the in-app floating bubble.
class ChittiVoiceInteractionSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession {
        return ChittiVoiceInteractionSession(this)
    }
}
