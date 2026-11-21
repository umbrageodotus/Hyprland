#include "IPointer.hpp"

const Vector2D& IPointer::SMotionEvent::effectiveDelta(bool forceNoAccel) const {
    return forceNoAccel ? unaccel : delta;
}

uint32_t IPointer::getCapabilities() {
    return HID_INPUT_CAPABILITY_POINTER;
}

eHIDType IPointer::getType() {
    return HID_TYPE_POINTER;
}
