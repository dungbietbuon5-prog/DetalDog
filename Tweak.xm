// language: Objective-C, file: Tweak.xm
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/vm_map.h>
#import <mach/mach.h>
#include <cmath>
#include <string.h>

#define OFF_GameFacade         0xA72E4E0
#define OFF_GameFacade_P2      0xB8
#define OFF_BaseGame_Match     0x90
#define OFF_Match_PlayerDict   0xC0
#define OFF_Match_LocalPlayer  0xD8
#define OFF_Dict_Entries       0x18
#define OFF_Dict_Count         0x20
#define OFF_Dict_ArrayHeader   0x20
#define OFF_Dict_EntryStride   0x18
#define OFF_Dict_EntryValue    0x10
#define OFF_Player_IsDead      0x7C
#define OFF_Player_HP          0x70
#define OFF_Player_Rotation    0x614
#define OFF_Bone_Head          0x6A0

static uintptr_t g_baseAddr = 0;
static bool aimbotEnabled = false;

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

void UpdateAimbot() {
    if (!aimbotEnabled) return;
    if (!g_baseAddr) g_baseAddr = get_base_address();
    if (!g_baseAddr) return;

    uintptr_t gameFacade = ReadMemory<uintptr_t>(g_baseAddr + OFF_GameFacade);
    if (!gameFacade) return;
    uintptr_t baseGame = ReadMemory<uintptr_t>(gameFacade + OFF_GameFacade_P2);
    if (!baseGame) return;
    uintptr_t match = ReadMemory<uintptr_t>(baseGame + OFF_BaseGame_Match);
    if (!match) return;
    uintptr_t localPlayer = ReadMemory<uintptr_t>(match + OFF_Match_LocalPlayer);
    if (!localPlayer) return;
    uintptr_t playerDict = ReadMemory<uintptr_t>(match + OFF_Match_PlayerDict);
    if (!playerDict) return;

    uintptr_t entries = ReadMemory<uintptr_t>(playerDict + OFF_Dict_Entries);
    int count = ReadMemory<int>(playerDict + OFF_Dict_Count);
    
    uintptr_t myHeadTransform = ReadMemory<uintptr_t>(localPlayer + OFF_Bone_Head);
    if (!myHeadTransform) return;
    Vector3 myPos = GetBonePosition(myHeadTransform);

    uintptr_t bestTarget = 0;
    float bestDistance = 9999.0f;
    Vector3 bestEnemyPos;

    for (int i = 0; i < count; i++) {
        uintptr_t entryAddr = entries + OFF_Dict_ArrayHeader + (i * OFF_Dict_EntryStride);
        uintptr_t enemyPlayer = ReadMemory<uintptr_t>(entryAddr + OFF_Dict_EntryValue);
        
        if (!enemyPlayer || enemyPlayer == localPlayer) continue;
        if (ReadMemory<bool>(enemyPlayer + OFF_Player_IsDead)) continue;

        uintptr_t enemyHeadTransform = ReadMemory<uintptr_t>(enemyPlayer + OFF_Bone_Head);
        if (!enemyHeadTransform) continue;
        
        Vector3 enemyPos = GetBonePosition(enemyHeadTransform);
        float dist = myPos.distance(enemyPos);
        
        if (dist < bestDistance) {
            bestDistance = dist;
            bestTarget = enemyPlayer;
            bestEnemyPos = enemyPos;
        }
    }

    if (bestTarget != 0 && bestDistance > 0.1f) {
        Vector3 dir = bestEnemyPos - myPos;
        float pitch = -asinf(dir.y / bestDistance) * (180.0f / 3.14159265f);
        float yaw = atan2f(dir.x, dir.z) * (180.0f / 3.14159265f);
        
        uintptr_t rotationAddr = localPlayer + OFF_Player_Rotation;
        
        vm_protect(mach_task_self(), rotationAddr, 8, false, VM_PROT_READ | VM_PROT_WRITE);
        float* angles = (float*)rotationAddr;
        angles[0] = pitch;
        angles[1] = yaw;
        vm_protect(mach_task_self(), rotationAddr, 8, false, VM_PROT_READ);
    }
}

// ==========================================
// GIAO DIỆN MENU CÓ NÚT NỔI TD
// ==========================================

@interface TrungDungMenuView : UIView
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIButton *toggleBtn;
@end

@implementation TrungDungMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.toggleBtn.frame = CGRectMake(0, 0, 50, 50);
        self.toggleBtn.backgroundColor = [UIColor colorWithRed:0.8 green:0.1 blue:0.1 alpha:0.9];
        [self.toggleBtn setTitle:@"TD" forState:UIControlStateNormal];
        [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.toggleBtn.layer.cornerRadius = 25;
        self.toggleBtn.layer.borderWidth = 2;
        self.toggleBtn.layer.borderColor = [UIColor whiteColor].CGColor;
        [self.toggleBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.toggleBtn];

        self.panel = [[UIView alloc] initWithFrame:CGRectMake(60, 0, 200, 100)];
        self.panel.backgroundColor = [UIColor colorWithRed:0.1 green:0.05 blue:0.05 alpha:0.9];
        self.panel.layer.cornerRadius = 10;
        self.panel.layer.borderWidth = 1;
        self.panel.layer.borderColor = [UIColor redColor].CGColor;
        self.panel.hidden = YES;
        
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, 100, 30)];
        lbl.text = @"Aim Kill (FF)";
        lbl.textColor = [UIColor whiteColor];
        [self.panel addSubview:lbl];
        
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(120, 15, 50, 30)];
        [sw addTarget:self action:@selector(toggleAim:) forControlEvents:UIControlEventValueChanged];
        [self.panel addSubview:sw];
        
        [self addSubview:self.panel];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self.toggleBtn addGestureRecognizer:pan];
    }
    return self;
}

- (void)toggleMenu { self.panel.hidden = !self.panel.hidden; }
- (void)toggleAim:(UISwitch *)s { aimbotEnabled = s.isOn; }
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:self];
}
@end

@interface TrungDungTimer : NSObject
+ (void)startLoop;
@end
@implementation TrungDungTimer
+ (void)startLoop {
    [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer * _Nonnull timer) {
        UpdateAimbot();
    }];
}
@end

%hook UIWindow
- (instancetype)initWithFrame:(CGRect)frame {
    id ret = %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            TrungDungMenuView *menu = [[TrungDungMenuView alloc] initWithFrame:CGRectMake(20, 100, 280, 150)];
            
            // Chỉ dùng connectedScenes, xóa sổ hàm windows cũ
            UIWindow *window = nil;
            for (UIScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
                if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                        if (w.isKeyWindow) { 
                            window = w; 
                            break; 
                        }
                    }
                }
            }
            
            if (window) {
                [window addSubview:menu];
            }
            
            [NSClassFromString(@"TrungDungTimer") startLoop];
        });
    });
    return ret;
}
%end
