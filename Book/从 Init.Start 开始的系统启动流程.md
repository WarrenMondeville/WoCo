# 从 Init.Start 开始的系统启动流程

## 1. 入口：Init.Start()

​        private void Start()

​        {

​            this.StartAsync().Coroutine();

​        }

Start() 调用 StartAsync()，通过 .Coroutine() 以协程方式执行异步逻辑。

------

## 2. 第一阶段：基础与资源初始化 (StartAsync)

### 2.1 基础设置 (L16–30)

- DontDestroyOnLoad(gameObject)：让 Init 对象不被场景切换销毁

- 设置 UnhandledException 异常捕获

- 解析命令行参数，得到 Options，并设置 StartConfig = "StartConfig/Localhost"

- 注册 Logger、ETTask 异常处理

### 2.2 核心单例 (L31–33)

- TimeInfo：时间信息

- FiberManager：Fiber 管理和调度

### 2.3 资源与代码加载 (L35–40)

1. ResourcesComponent.CreatePackageAsync("DefaultPackage", true)：初始化资源包

1. CodeLoader.DownloadAsync()：加载热更新 DLL（非 Editor 下从 Bundle 加载）

1. CodeLoader.Start()：真正拉起业务逻辑

------

## 3. CodeLoader.Start()：加载程序集并启动业务

​        public void Start()

​        {

​            // ... 根据 IsEditor / EnableDll 加载 Unity.Model、ModelView、Hotfix、HotfixView 程序集

​            (Assembly hotfixAssembly, Assembly hotfixViewAssembly) = this.LoadHotfix();

​            World.Instance.AddSingleton<CodeTypes, Assembly[]>(...);  // 注册所有程序集到 CodeTypes

​            IStaticMethod start = new StaticMethod(this.modelAssembly, "ET.Entry", "Start");

​            start.Run();  // 反射调用 ET.Entry.Start()

​        }

CodeLoader.Start()

 完成三

件事：

1. 加载 Model / ModelView / Hotfix / HotfixView 程序集

1. 注册到 CodeTypes

1. 反射调用 ET.Entry.Start()

------

## 4. Entry.Start()：业务启动入口

​        public static void Start()

​        {

​            StartAsync().Coroutine();

​        }

​        

​        private static async ETTask StartAsync()

​        {

​            WinPeriod.Init();

​            MongoRegister.Init();

​            EntitySerializeRegister.Init();

​            World.Instance.AddSingleton<IdGenerater>();

​            World.Instance.AddSingleton<OpcodeType>();

​            World.Instance.AddSingleton<ObjectPool>();

​            World.Instance.AddSingleton<MessageQueue>();

​            World.Instance.AddSingleton<NetServices>();

​            World.Instance.AddSingleton<NavmeshComponent>();

​            World.Instance.AddSingleton<LogMsg>();

​            CodeTypes.Instance.CreateCode();  // 创建事件、组件等 Code

​            await World.Instance.AddSingleton<ConfigLoader>().LoadAsync();  // 加载配置

​            await FiberManager.Instance.Create(SchedulerType.Main, ConstFiberId.Main, 0, SceneType.Main, "");

​        }

流程：注册 Mongo、Entity 序列化 → 创建全局单例 → 初始化 CodeTypes → 加载配置 → 创建主 Fiber。

------

## 5. Fiber 创建与 FiberInit 分发

FiberManager.Create() 中：

​        public async ETTask<int> Create(SchedulerType schedulerType, int fiberId, int zone, SceneType sceneType, string name)

​        {

​            Fiber fiber = new(fiberId, zone, sceneType, name);

​            this.fibers.TryAdd(fiberId, fiber);

​            this.schedulers[(int) schedulerType].Add(fiberId);  // 加入 MainThreadScheduler

​            fiber.ThreadSynchronizationContext.Post(async () =>

​            {

​                await EventSystem.Instance.Invoke<FiberInit, ETTask>((long)sceneType, new FiberInit() {Fiber = fiber});

​                tcs.SetResult(true);

​            });

​            await tcs.Task;

​            return fiberId;

​        }

- 创建 Fiber，并构造 Root Scene

- 把 fiber 加入 Main 调度器

- 在 fiber 的同步上下文中调用 EventSystem.Invoke<FiberInit, ETTask>((long)SceneType.Main, ...)，分发到 FiberInit_Main

------

## 6. FiberInit_Main：三层初始化事件

namespace ET

{

​    [Invoke((long)SceneType.Main)]

​    public class FiberInit_Main: AInvokeHandler<FiberInit, ETTask>

​    {

​        public override async ETTask Handle(FiberInit fiberInit)

​        {

​            Scene root = fiberInit.Fiber.Root;

​           

​            await EventSystem.Instance.PublishAsync(root, new EntryEvent1());

​            await EventSystem.Instance.PublishAsync(root, new EntryEvent2());

​            await EventSystem.Instance.PublishAsync(root, new EntryEvent3());

​        }

​    }

}

| 事件        | Handler                | 作用                                                         |
| ----------- | ---------------------- | ------------------------------------------------------------ |
| EntryEvent1 | EntryEvent1_InitShare  | 共享组件：TimerComponent、CoroutineLockComponent、ObjectWait、MailBoxComponent、ProcessInnerSender |
| EntryEvent2 | EntryEvent2_InitServer | 服务器：按配置创建 NetInner、Realm、Gate、Map 等 Fiber；或 Watcher/Console |
| EntryEvent3 | EntryEvent3_InitClient | 客户端：GlobalComponent、UI、ResourcesLoader、Player 等，并发布 AppStartInitFinish |

------

## 7. 主循环驱动：Update / LateUpdate

​        private void Update()

​        {

​            TimeInfo.Instance.Update();

​            FiberManager.Instance.Update();

​        }

​        private void LateUpdate()

​        {

​            FiberManager.Instance.LateUpdate();

​        }

每帧：

1. TimeInfo.Update()：更新时间

1. FiberManager.Update() → MainThreadScheduler.Update()：

- 处理主线程同步上下文

- 遍历主线程 Fiber，设置 Fiber.Instance，调用 fiber.Update()（内部是 EntitySystem.Update()），处理本帧逻辑

1. FiberManager.LateUpdate()：执行 Fiber 的 LateUpdate

------

## 8. 整体流程概览

Init.Start()

​    └─ StartAsync().Coroutine()

​           ├─ 异常捕获、Options、Logger

​           ├─ TimeInfo、FiberManager

​           ├─ ResourcesComponent.CreatePackageAsync()

​           ├─ CodeLoader.DownloadAsync()

​           └─ CodeLoader.Start()

​                  ├─ 加载 Model/ModelView/Hotfix/HotfixView

​                  ├─ CodeTypes 注册

​                  └─ ET.Entry.Start()

​                         ├─ Mongo/Entity 注册、全局单例

​                         ├─ CodeTypes.CreateCode()

​                         ├─ ConfigLoader.LoadAsync()

​                         └─ FiberManager.Create(Main)

​                                ├─ 创建 Fiber + Root Scene

​                                └─ EventSystem.Invoke<FiberInit>()

​                                       └─ FiberInit_Main.Handle()

​                                              ├─ PublishAsync(EntryEvent1)

​                                              ├─ PublishAsync(EntryEvent2)

​                                              └─ PublishAsync(EntryEvent3)

每帧：

Init.Update() → TimeInfo.Update() → FiberManager.Update() → 各 Fiber.EntitySystem.Update()

Init.LateUpdate() → FiberManager.LateUpdate() → 各 Fiber.LateUpdate()

------

## 9. 核心设计点

1. 单例与生命周期：World 管理所有单例，在 OnApplicationQuit 时 World.Dispose() 统一释放。

1. Fiber + Actor：每个 Fiber 有独立 Scene、EntitySystem、消息队列，跨 Fiber 只通过消息通信。

1. 事件驱动：Fiber 初始化通过 FiberInit + EntryEvent1/2/3 分步完成，不同 AppType（Server/Client/Watcher）走不同分支。

1. 热更新：Hotfix/HotfixView 独立程序集，可在 CodeLoader.Reload() 中热更，无需重跑进程。