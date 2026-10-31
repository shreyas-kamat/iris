import sys
import time
import subprocess
import ctypes

cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')

class CGPoint(ctypes.Structure):
    _fields_ = [('x', ctypes.c_double), ('y', ctypes.c_double)]

kCGEventLeftMouseDown = 1
kCGEventLeftMouseUp = 2
kCGMouseButtonLeft = 0
kCGHIDEventTap = 0

cg.CGEventCreateMouseEvent.restype = ctypes.c_void_p
cg.CGEventCreateMouseEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint32, CGPoint, ctypes.c_uint32]
cg.CGEventPost.restype = None
cg.CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]

IPAD_UDID = "EEF5AD85-7D30-4EF3-90A6-B79A80AD6B44"

# Window top-left is at (268, 25), size 694x950
# Phone screen inside window:
# Left = 38, Right = 656 -> W = 618
# Top = 70, Bottom = 910 -> H = 840
WIN_X = 268.0
WIN_Y = 25.0
SCR_LEFT = 38.0
SCR_TOP = 70.0
SCR_W = 618.0
SCR_H = 840.0

def sim_to_screen(px, py):
    # px in [0, 2048], py in [0, 2732]
    win_x = WIN_X + SCR_LEFT + (px / 2048.0) * SCR_W
    win_y = WIN_Y + SCR_TOP + (py / 2732.0) * SCR_H
    return win_x, win_y

def click_screen(sx, sy):
    point = CGPoint(sx, sy)
    down = cg.CGEventCreateMouseEvent(None, kCGEventLeftMouseDown, point, kCGMouseButtonLeft)
    up = cg.CGEventCreateMouseEvent(None, kCGEventLeftMouseUp, point, kCGMouseButtonLeft)
    cg.CGEventPost(kCGHIDEventTap, down)
    time.sleep(0.06)
    cg.CGEventPost(kCGHIDEventTap, up)
    time.sleep(0.5)

def click_sim(px, py):
    sx, sy = sim_to_screen(px, py)
    click_screen(sx, sy)

def screenshot(filename):
    subprocess.run(["xcrun", "simctl", "io", IPAD_UDID, "screenshot", filename], check=True)

if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'click_sim':
        click_sim(float(sys.argv[2]), float(sys.argv[3]))
    elif cmd == 'click_screen':
        click_screen(float(sys.argv[2]), float(sys.argv[3]))
    elif cmd == 'shot':
        screenshot(sys.argv[2])
