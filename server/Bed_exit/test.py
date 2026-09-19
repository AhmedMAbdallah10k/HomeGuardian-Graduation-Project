"""test.py — Run: python test.py"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from main import StateMachine, torso_rise, leg_xs, body_center_x


if __name__ == "__main__":

    BED_BOX = {"x1":100,"y1":100,"x2":500,"y2":400}
    # bed height=300, torso threshold=300*0.20=60px
    # leg trigger: x<80 or x>520
    # TORSO_MIN_FRAMES=6, FOOT_MIN_FRAMES=4

    PASS = FAIL = 0
    def check(label, ok):
        global PASS, FAIL
        PASS+=ok; FAIL+=not ok
        print(f"  [{'PASS' if ok else 'FAIL'}] {label}")

    def kp(shoulder_y, hip_y, knee_x, ankle_x, v=True):
        """Build keypoints. shoulder_y < hip_y = sitting up."""
        return {
            "nose":           {"x":300,"y":shoulder_y-30,"v":v},
            "left_shoulder":  {"x":280,"y":shoulder_y,   "v":v},
            "right_shoulder": {"x":320,"y":shoulder_y,   "v":v},
            "left_elbow":     {"x":260,"y":shoulder_y+30,"v":v},
            "right_elbow":    {"x":340,"y":shoulder_y+30,"v":v},
            "left_wrist":     {"x":250,"y":shoulder_y+60,"v":v},
            "right_wrist":    {"x":350,"y":shoulder_y+60,"v":v},
            "left_hip":       {"x":285,"y":hip_y,        "v":v},
            "right_hip":      {"x":315,"y":hip_y,        "v":v},
            "left_knee":      {"x":knee_x-10,"y":hip_y+60,"v":v},
            "right_knee":     {"x":knee_x,   "y":hip_y+60,"v":v},
            "left_ankle":     {"x":ankle_x-10,"y":hip_y+120,"v":v},
            "right_ankle":    {"x":ankle_x,   "y":hip_y+120,"v":v},
            "left_heel":      {"x":ankle_x-15,"y":hip_y+125,"v":v},
            "right_heel":     {"x":ankle_x-5, "y":hip_y+125,"v":v},
            "left_foot":      {"x":ankle_x-10,"y":hip_y+130,"v":v},
            "right_foot":     {"x":ankle_x,   "y":hip_y+130,"v":v},
        }

    # Lying flat: shoulder_y=250, hip_y=250 → torso_rise=0
    # Sitting up: shoulder_y=150, hip_y=250 → torso_rise=100 > threshold=60

    def frames(sm, n, sy, hy, kx, ax, cg=False):
        out=(0,"none","")
        for _ in range(n): out=sm.update(kp(sy,hy,kx,ax), BED_BOX, cg)
        return out

    def reach_state1(sm):
        sm.update(kp(250,250,300,300), BED_BOX, False)  # baseline
        frames(sm, 12, 150, 250, 300, 300)              # sit up, well above TORSO_MIN_FRAMES=6

    print("\n── 1: Helpers ───────────────────────────────────────────────────────")
    k = kp(250,250,300,300)
    check("torso_rise=0 when flat",     abs(torso_rise(k)) < 1)
    k2 = kp(150,250,300,300)
    check("torso_rise>0 when sitting",  torso_rise(k2) > 50)
    check("leg_xs returns values",      len(leg_xs(k)) > 0)
    check("body_center_x in range",     100 < body_center_x(k) < 500)

    print("\n── 2: Baseline ──────────────────────────────────────────────────────")
    sm = StateMachine()
    sm.update(kp(250,250,300,300), BED_BOX, False)
    check("State 0",                    sm.state == 0)
    check("Baseline set",               sm.baseline_rise is not None)

    print("\n── 3: Resting — no alert ────────────────────────────────────────────")
    sm = StateMachine()
    sm.update(kp(250,250,300,300), BED_BOX, False)
    s,a,_ = frames(sm, 30, 250, 250, 300, 300)
    check("Stays State 0",              s == 0)
    check("No alert",                   a == "none")

    print("\n── 4: Sit up then lie back — no alert ───────────────────────────────")
    sm = StateMachine()
    reach_state1(sm)
    check("State 1",                    sm.state == 1)
    s,a,_ = frames(sm, 8, 250, 250, 300, 300)
    check("State 0 after lying back",   s == 0)
    check("No alert",                   a == "none")

    print("\n── 5: Legs over edge — alert fires ──────────────────────────────────")
    sm = StateMachine()
    reach_state1(sm)
    s,a,_ = frames(sm, 8, 150, 250, 540, 540)  # ankles/knees at x=540 > 520
    check("State 2",                    s == 2)
    check("early_warning",              a == "early_warning")

    print("\n── 6: Caregiver present — assisted ──────────────────────────────────")
    sm = StateMachine()
    reach_state1(sm)
    s,a,_ = frames(sm, 8, 150, 250, 540, 540, cg=True)
    check("State stays at 1",           s == 1)
    check("assisted",                   a == "assisted")

    print("\n── 7: Jitter — no trigger ───────────────────────────────────────────")
    sm = StateMachine()
    reach_state1(sm)
    sm.update(kp(150,250,540,540), BED_BOX, False)  # 1 frame outside
    sm.update(kp(150,250,300,300), BED_BOX, False)  # back inside
    s,_,_ = sm.update(kp(150,250,300,300), BED_BOX, False)
    check("Still State 1",              s == 1)

    print("\n── 8: No keypoints — state frozen ───────────────────────────────────")
    sm = StateMachine()
    reach_state1(sm)
    s,a,_ = sm.update(None, BED_BOX, False)
    check("Frozen at 1",                s == 1)
    check("No alert",                   a == "none")

    print("\n── 9: Full exit via body center ─────────────────────────────────────")
    sm = StateMachine()
    reach_state1(sm)
    frames(sm, 8, 150, 250, 540, 540)   # reach State 2
    # body center x=600 > 500+40=540 → State 3
    k_exit = kp(150,250,600,600)
    for _n in ("left_shoulder","right_shoulder","left_hip","right_hip"):
        k_exit[_n]["x"] = 600
    s,a,_ = sm.update(k_exit, BED_BOX, False)
    check("State 3",                    s == 3)
    check("critical",                   a == "critical")

    print("\n── 10: Reset ────────────────────────────────────────────────────────")
    sm = StateMachine()
    reach_state1(sm)
    sm.reset()
    check("State 0",                    sm.state == 0)
    check("Baseline cleared",           sm.baseline_rise is None)

    total = PASS+FAIL
    print(f"\n{'='*50}")
    print(f"Results: {PASS}/{total} passed {'✓' if not FAIL else '✗'}")
    print(f"{'='*50}\n")
    sys.exit(0 if not FAIL else 1)