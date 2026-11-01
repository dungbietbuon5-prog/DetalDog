// language: Objective-C, file: Tweak.xm
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/vm_map.h>
#import <mach/mach.h>
#include <cmath>
#include <string.h>

// ==========================================
// TOÀN BỘ OFFSET
// ==========================================
#define GameFacade                  0xA72E4E0
#define GameFacade_P2               0xB8
#define BaseGame_Match              0x90
#define Match_PlayerDict            0xC0
#define Match_LocalPlayer           0xD8

#define Dict_Entries                0x18
#define Dict_Count                  0x20
#define Dict_ArrayHeader            0x20
#define Dict_EntryStride            0x18
#define Dict_EntryValue             0x10

#define Player_Rotation             0x614
#define Player_HP                   0x70
#define Player_Armor                0x74
#define Player_IsDead               0x7C
#define Player_IsKnocked            0x1258
#define Player_IsKnockedFrozen      0xB0  // <-- Dòng bị thiếu đã được thêm vào đây
#define Player_Name                 0x490
#define Player_FOVOffset            0x84
#define Player_IsFiring             0x848
#define Player_Weapon               0x600
#define Weapon_Recoil               0x18

// Bones
#define Bone_Head                   0x6A0
#define Bone_Hip                    0x6A8
#define Bone_Breast                 0x6B0
#define Bone_Root                   0x6C8
#define Bone_LeftHand               0x720
#define Bone_RightHand              0x718
#define Bone_LeftFoot               0x6D8
#define Bone_RightFoot              0x6E0

static uintptr_t g_baseAddr = 0;

// ==========================================
// BIẾN TRẠNG THÁI
// ==========================================
static bool aimHead = false;
static bool aimNeck = false;
static bool noRecoil = false;
static bool fastFire = false;
static bool fovHack = false;
static bool freezeEnemy = false;
static bool espEnabled = false;

// ==========================================
// HÀM TIỆN ÍCH
// ==========================================
uintptr_t get_base_address() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && (strstr(name, "UnityFramework") || strstr(name, "FreeFire"))) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

template <typename T>
T ReadMemory(uintptr_t address) {
    T empty_val;
    memset(&empty_val, 0, sizeof(T));
    if (address < 0x100000000 || address > 0x7FFFFFFFFFFF) return empty_val;
    return *(T*)(address);
}

void WriteMemory(uintptr_t address, void* value, size_t size) {
    if (address < 0x100000000 || address > 0x7FFFFFFFFFFF) return;
    vm_protect(mach_task_self(), address, size, false, VM_PROT_READ | VM_PROT_WRITE);
    memcpy((void*)address, value, size);
    vm_protect(mach_task_self(), address, size, false, VM_PROT_READ);
}

struct Matrix { float m[16]; };
struct Vector3 {
    float x, y, z;
    Vector3() : x(0), y(0), z(0) {}
    Vector3(float _x, float _y, float _z) : x(_x), y(_y), z(_z) {}
    Vector3 operator-(const Vector3& v) const { return Vector3(x - v.x, y - v.y, z - v.z); }
    float distance(const Vector3& v) const {
        return sqrtf(powf(x - v.x, 2) + powf(y - v.y, 2) + powf(z - v.z, 2));
    }
};

Vector3 GetBonePosition(uintptr_t transformPtr) {
    if (!transformPtr) return Vector3();
    Matrix mat = ReadMemory<Matrix>(transformPtr + 0x90); 
    return Vector3(mat.m[12], mat.m[13], mat.m[14]); 
}

// ==========================================
// LOGIC GAME
// ==========================================
void UpdateGame() {
    if (!g_baseAddr) g_baseAddr = get_base_address();
    if (!g_baseAddr) return;

    uintptr_t gameFacade = ReadMemory<uintptr_t>(g_baseAddr + GameFacade);
    if (!gameFacade) return;
    uintptr_t baseGame = ReadMemory<uintptr_t>(gameFacade + GameFacade_P2);
    if (!baseGame) return;
    uintptr_t match = ReadMemory<uintptr_t>(baseGame + BaseGame_Match);
    if (!match) return;
    uintptr_t localPlayer = ReadMemory<uintptr_t>(match + Match_LocalPlayer);
    if (!localPlayer) return;

    uintptr_t playerDict = ReadMemory<uintptr_t>(match + Match_PlayerDict);
    uintptr_t entries = ReadMemory<uintptr_t>(playerDict + Dict_Entries);
    int count = ReadMemory<int>(playerDict + Dict_Count);

    uintptr_t myBoneTF = ReadMemory<uintptr_t>(localPlayer + Bone_Head);
    Vector3 myPos = GetBonePosition(myBoneTF);

    // AIMBOT
    if (aimHead || aimNeck) {
        uintptr_t bestTarget = 0;
        float bestDist = 9999.0f;
        Vector3 bestEnemyPos;

        for (int i = 0; i < count; i++) {
            uintptr_t entryAddr = entries + Dict_ArrayHeader + (i * Dict_EntryStride);
            uintptr_t enemy = ReadMemory<uintptr_t>(entryAddr + Dict_EntryValue);
            
            if (!enemy || enemy == localPlayer) continue;
            if (ReadMemory<bool>(enemy + Player_IsDead)) continue;
            if (ReadMemory<bool>(enemy + Player_IsKnocked)) continue;

            uintptr_t enemyBoneTF = ReadMemory<uintptr_t>(enemy + (aimHead ? Bone_Head : Bone_Breast));
            if (!enemyBoneTF) continue;
            
            Vector3 enemyPos = GetBonePosition(enemyBoneTF);
            float dist = myPos.distance(enemyPos);
            
            if (dist < bestDist) {
                bestDist = dist;
                bestTarget = enemy;
                bestEnemyPos = enemyPos;
            }
        }

        if (bestTarget != 0 && bestDist > 0.1f) {
            Vector3 dir = bestEnemyPos - myPos;
            float pitch = -asinf(dir.y / bestDist) * (180.0f / 3.14159265f);
            float yaw = atan2f(dir.x, dir.z) * (180.0f / 3.14159265f);
            float angles[2] = {pitch, yaw};
            WriteMemory(localPlayer + Player_Rotation, angles, 8);
        }
    }

    // NO RECOIL
    if (noRecoil) {
        uintptr_t weaponPtr = ReadMemory<uintptr_t>(localPlayer + Player_Weapon);
        if (weaponPtr) {
            float zero = 0.0f;
            WriteMemory(weaponPtr + Weapon_Recoil, &zero, 4);
        }
    }

    // FAST FIRE
    if (fastFire) {
        bool firing = true;
        WriteMemory(localPlayer + Player_IsFiring, &firing, 1);
    }

    // FOV
    if (fovHack) {
        float fov = 120.0f;
        WriteMemory(localPlayer + Player_FOVOffset, &fov, 4);
    }

    // FREEZE ENEMY
    if (freezeEnemy) {
        for (int i = 0; i < count; i++) {
            uintptr_t entryAddr = entries + Dict_ArrayHeader + (i * Dict_EntryStride);
            uintptr_t enemy = ReadMemory<uintptr_t>(entryAddr + Dict_EntryValue);
            if (enemy && enemy != localPlayer) {
                bool freeze = true;
                WriteMemory(enemy + Player_IsKnockedFrozen, &freeze, 1);
            }
        }
    }
}

// ==========================================
// GIAO DIỆN MENU
// ==========================================
static id sharedMenu = nil;

@interface TrungDungMenuView : UIView
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIButton *toggleBtn;
@end

@implementation TrungDungMenuView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        
        self.toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.toggleBtn.frame = CGRectMake(0, 0, 50, 50);
        self.toggleBtn.backgroundColor = [UIColor colorWithRed:0.8 green:0.1 blue:0.1 alpha:0.9];
        [self.toggleBtn setTitle:@"TD" forState:UIControlStateNormal];
        self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        self.toggleBtn.layer.cornerRadius = 25;
        [self.toggleBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.toggleBtn];

        self.panel = [[UIView alloc] initWithFrame:CGRectMake(60, -150, 220, 420)];
        self.panel.backgroundColor = [UIColor colorWithRed:0.1 green:0.05 blue:0.05 alpha:0.95];
        self.panel.layer.cornerRadius = 10;
        self.panel.layer.borderWidth = 1;
        self.panel.layer.borderColor = [UIColor redColor].CGColor;
        self.panel.hidden = YES; 
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.frame = CGRectMake(190, 5, 25, 25);
        [closeBtn setTitle:@"X" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
        [self.panel addSubview:closeBtn];

        [self addSwitch:@"Aim Head" yPos:40 action:@selector(toggleAimHead:)];
        [self addSwitch:@"Aim Neck" yPos:85 action:@selector(toggleAimNeck:)];
        [self addSwitch:@"No Recoil" yPos:130 action:@selector(toggleRecoil:)];
        [self addSwitch:@"Fast Fire" yPos:175 action:@selector(toggleFastFire:)];
        [self addSwitch:@"FOV 120" yPos:220 action:@selector(toggleFov:)];
        [self addSwitch:@"Freeze Enemy" yPos:265 action:@selector(toggleFreeze:)];

        [self addSubview:self.panel];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self.toggleBtn addGestureRecognizer:pan];
    }
    return self;
}

- (void)addSwitch:(NSString *)title yPos:(CGFloat)y action:(SEL)action {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 130, 30)];
    lbl.text = title;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.panel addSubview:lbl];
    
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(145, y, 50, 30)];
    sw.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:sw];
}

- (void)toggleMenu { self.panel.hidden = !self.panel.hidden; }
- (void)closeMenu { self.panel.hidden = YES; }

- (void)toggleAimHead:(UISwitch *)s { aimHead = s.isOn; if(s.isOn) aimNeck = NO; }
- (void)toggleAimNeck:(UISwitch *)s { aimNeck = s.isOn; if(s.isOn) aimHead = NO; }
- (void)toggleRecoil:(UISwitch *)s { noRecoil = s.isOn; }
- (void)toggleFastFire:(UISwitch *)s { fastFire = s.isOn; }
- (void)toggleFov:(UISwitch *)s { fovHack = s.isOn; }
- (void)toggleFreeze:(UISwitch *)s { freezeEnemy = s.isOn; }

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:self];
}
@end

// ==========================================
// VÒNG LẶP & KHỞI TẠO
// ==========================================
@interface TrungDungTimer : NSObject
+ (void)startLoop;
@end
@implementation TrungDungTimer
+ (void)startLoop {
    [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer * _Nonnull timer) {
        UpdateGame();
    }];
}
@end

__attribute__((constructor))
static void initialize_menu() {
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
        if (!sharedMenu) {
            sharedMenu = [[TrungDungMenuView alloc] initWithFrame:CGRectMake(20, 150, 280, 220)];
            [NSClassFromString(@"TrungDungTimer") startLoop];
        }
        
        UIWindow *keyWindow = nil;
        for (UIScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { keyWindow = w; break; }
                }
            }
        }
        
        if (keyWindow) {
            if ([sharedMenu superview] != keyWindow) {
                [sharedMenu removeFromSuperview];
                [keyWindow addSubview:sharedMenu];
                [keyWindow bringSubviewToFront:sharedMenu];
            }
        }
    }];
}
