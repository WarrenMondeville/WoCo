# EventSystem 源码解析

本文档分析 ET 框架中 `EventSystem.cs` 的实现原理与工作机制。

## 一、概述

`EventSystem` 是 ET 框架的事件与调用分发系统，提供两类核心能力：

1. **Publish（事件发布）**：发布-订阅模式，支持多模块解耦，事件可以没有订阅者
2. **Invoke（调用分发）**：类似函数调用，必须有对应的处理器，否则抛异常

```csharp
// EventSystem 定义
[Code]
public class EventSystem: Singleton<EventSystem>, ISingletonAwake
```

- 单例模式，实现 `ISingletonAwake` 在启动时初始化
- `[Code]` 标记为框架核心代码（通常不参与热更）

---

## 二、核心数据结构

### 2.1 EventInfo（内部类）

```csharp
private class EventInfo
{
    public IEvent IEvent { get; }      // 事件处理器实例
    public SceneType SceneType { get; } // 生效的场景类型
}
```

封装单个事件处理器的实例及其作用的 `SceneType`，用于按场景过滤事件。

### 2.2 注册表

| 变量 | 类型 | 含义 |
|------|------|------|
| `allEvents` | `Dictionary<Type, List<EventInfo>>` | 事件类型 → 处理器列表 |
| `allInvokers` | `Dictionary<Type, Dictionary<long, object>>` | 参数类型 → (type 键 → 处理器实例) |

- **allEvents**：按事件参数类型 `T`（`struct`）索引，同一事件可被多个处理器订阅
- **allInvokers**：按参数类型 `A` 和 `type`（long）索引，每个 `(A, type)` 对应唯一处理器

---

## 三、初始化流程（Awake）

`EventSystem.Awake()` 在加载 Dll 后调用，通过反射扫描并注册所有事件与调用处理器。

### 3.1 注册 Event 处理器

```
CodeTypes.GetTypes(typeof(EventAttribute))
    → 遍历每个带 [Event(SceneType)] 的类型
    → 创建 IEvent 实例
    → 读取 EventAttribute.SceneType
    → 以 AEvent<S,A>.Type（即 typeof(A)）为键，加入 allEvents
```

要点：

- 一个事件类可以有多个 `[Event(xxx)]` 属性，会分别注册
- 键为**事件参数类型** `A`，而非 `S`（Scene 类型）

### 3.2 注册 Invoke 处理器

```
CodeTypes.GetTypes(typeof(InvokeAttribute))
    → 遍历每个带 [Invoke(type)] 的类型
    → 创建 IInvoke 实例
    → 以 IInvoke.Type（参数类型）和 InvokeAttribute.Type（long）为键，加入 allInvokers
```

- `InvokeAttribute.Type` 默认为 0
- 同一 `(参数类型, type)` 重复注册会抛异常

---

## 四、Publish（事件发布）

### 4.1 异步发布：PublishAsync

```csharp
public async ETTask PublishAsync<S, T>(S scene, T a) 
    where S: class, IScene 
    where T : struct
```

流程：

1. 用 `typeof(T)` 从 `allEvents` 取处理器列表
2. 无订阅者则直接返回
3. 过滤：只保留 `scene.SceneType.HasSameFlag(eventInfo.SceneType)` 的处理器
4. 并行执行所有通过筛选的 `Handle(scene, a)`（`ETTask`）
5. 使用 `ETTaskHelper.WaitAll` 等待全部完成
6. 异常在 `Handle` 内部被捕获并打日志，不会向外抛出

### 4.2 同步发布：Publish

```csharp
public void Publish<S, T>(S scene, T a) where S: class, IScene where T : struct
```

- 逻辑与 `PublishAsync` 类似，但通过 `.Coroutine()` 启动协程，不 await
- 适合“发射后不管”的场景，不等待处理器执行完毕

### 4.3 SceneType 过滤

`HasSameFlag` 用于判断场景类型是否匹配（支持多场景组合）。

示例：`[Event(SceneType.Current)]` 的处理器只会在 `scene.SceneType` 包含 `Current` 时执行。

---

## 五、Invoke（调用分发）

### 5.1 Invoke 与 Publish 的区别（摘自源码注释）

| 特性 | Invoke | Publish |
|------|--------|---------|
| 性质 | 类似函数调用 | 事件发布 |
| 订阅方 | 必须有处理器，否则异常 | 可以无订阅者 |
| 使用场景 | 同模块内部，需明确调用目标 | 跨模块解耦 |
| 示例 | Config 加载、Timer 按 Id 分发 | 任务系统订阅道具使用事件 |

**原则**：能用普通函数就不要用 Invoke，避免降低可读性。

### 5.2 无返回值：Invoke\<A\>

```csharp
public void Invoke<A>(long type, A args) where A: struct
```

- 根据 `typeof(A)` 和 `type` 查找 `AInvokeHandler<A>`
- 找不到或类型不符时抛异常（error1/2/3）
- 找到后调用 `Handle(args)`

### 5.3 有返回值：Invoke\<A, T\>

```csharp
public T Invoke<A, T>(long type, A args) where A: struct
```

- 查找 `AInvokeHandler<A, T>`
- 返回 `Handle(args)` 的结果

### 5.4 便捷重载

```csharp
public void Invoke<A>(A args) where A: struct  => Invoke(0, args);
public T Invoke<A, T>(A args) where A: struct  => Invoke<A, T>(0, args);
```

`type = 0` 时使用默认处理器。

---

## 六、接口与基类

### 6.1 Event 相关

**IEvent**

```csharp
public interface IEvent
{
    Type Type { get; }  // 返回事件参数类型 typeof(A)
}
```

**AEvent\<S, A\>**

```csharp
public abstract class AEvent<S, A>: IEvent 
    where S: class, IScene 
    where A: struct
{
    public Type Type => typeof(A);
    protected abstract ETTask Run(S scene, A a);
    public async ETTask Handle(S scene, A a) { ... }  // 调用 Run 并捕获异常
}
```

- 实现类只需实现 `Run(S scene, A a)`
- 异常在 `Handle` 中被 `Log.Error` 记录

### 6.2 Invoke 相关

**IInvoke**

```csharp
public interface IInvoke
{
    Type Type { get; }  // 参数类型
}
```

**AInvokeHandler\<A\>**（无返回值）

```csharp
public abstract class AInvokeHandler<A>: HandlerObject, IInvoke 
    where A: struct
{
    public abstract void Handle(A args);
}
```

**AInvokeHandler\<A, T\>**（有返回值）

```csharp
public abstract class AInvokeHandler<A, T>: HandlerObject, IInvoke 
    where A: struct
{
    public abstract T Handle(A args);
}
```

### 6.3 属性定义

**EventAttribute**

```csharp
public class EventAttribute: BaseAttribute
{
    public SceneType SceneType { get; }
    public EventAttribute(SceneType sceneType) { ... }
}
```

**InvokeAttribute**

```csharp
public class InvokeAttribute: BaseAttribute
{
    public long Type { get; }  // 默认 0
    public InvokeAttribute(long type = 0) { ... }
}
```

---

## 七、使用示例

### 7.1 Publish 示例

**定义事件参数（struct）**

```csharp
public struct ChangePosition { public Unit Unit; public Vector3 OldPos; }
```

**发布事件**

```csharp
EventSystem.Instance.Publish(this.Scene(), new ChangePosition() { Unit = this, OldPos = oldPos });
```

**订阅事件**

```csharp
[Event(SceneType.Current)]
public class ChangePosition_SyncGameObjectPos: AEvent<Scene, ChangePosition>
{
    protected override async ETTask Run(Scene scene, ChangePosition args)
    {
        // 同步 GameObject 位置到 Unit.Position
        Unit unit = args.Unit;
        var gameObjectComponent = unit.GetComponent<GameObjectComponent>();
        if (gameObjectComponent != null)
            gameObjectComponent.Transform.position = unit.Position;
        await ETTask.CompletedTask;
    }
}
```

### 7.2 Invoke 示例

**定义参数与处理器**

```csharp
// 参数
public struct GetAllConfigBytes { }

// 处理器
[Invoke]
public class GetAllConfigBytes: AInvokeHandler<ConfigLoader.GetAllConfigBytes, ETTask<Dictionary<Type, byte[]>>>
{
    public override async ETTask<Dictionary<Type, byte[]>> Handle(ConfigLoader.GetAllConfigBytes args)
    {
        // 加载配置逻辑...
        return output;
    }
}
```

**调用**

```csharp
var configBytes = await EventSystem.Instance.Invoke<GetAllConfigBytes, ETTask<Dictionary<Type, byte[]>>>(new GetAllConfigBytes());
```

**按 type 分发的 Invoke**

```csharp
// 按 SceneType 分发 Fiber 初始化
[Invoke((long)SceneType.Gate)]
public class FiberInit_Gate: AInvokeHandler<FiberInit, ETTask>
{
    public override async ETTask Handle(FiberInit fiberInit) { ... }
}

// 调用
await EventSystem.Instance.Invoke<FiberInit, ETTask>((long)sceneType, new FiberInit() { Fiber = fiber });
```

---

## 八、总结

| 特性 | 说明 |
|------|------|
| 注册时机 | Awake 时通过 CodeTypes 反射扫描 |
| 事件键 | `allEvents` 以事件参数类型 `typeof(T)` 为键 |
| 调用键 | `allInvokers` 以参数类型 + `InvokeAttribute.Type` 为键 |
| Scene 过滤 | Event 通过 `SceneType.HasSameFlag` 过滤 |
| 异步 | PublishAsync 并行执行所有处理器并 WaitAll |
| 同步 | Publish 通过 Coroutine 启动，不等待 |
| 异常 | Event 在 Handle 内捕获；Invoke 未找到处理器会抛异常 |

`EventSystem` 通过 Publish 实现模块解耦，通过 Invoke 实现按类型分发的“间接调用”，是 ET 框架中事件与初始化流程的核心组件。
