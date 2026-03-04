namespace ET
{
    public static partial class ErrorCode
    {
        public const int ERR_Success = 0;

        // 1-11004 是SocketError请看SocketError定义
        //-----------------------------------
        // 100000-109999是Core层的错误

        // 110000以下的错误请看ErrorCore.cs

        // 这里配置逻辑层的错误码
        // 110000 - 200000是抛异常的错误
        // 200001以上不抛异常



        public const int ERR_NetWorkError = 200002;//网络错误
        public const int ERR_LoginInfoError = 200003;//登录信息错误
        public const int ERR_AcountNameFormError = 200004;//登录账号格式错误
        public const int ERR_PasswordFormError = 200005;//登录密码格式错误
        public const int ERR_AccountInBlackListError = 200006;//账号处于黑名单中
        public const int ERR_LoginPasswordError = 200007;//登录密码错误
        public const int ERR_RequestRepeatedly = 200008;//反复请求多次
        public const int ERR_TokenError = 200009;//令牌错误
        public const int ERR_RoleNameIsNull = 200010;//角色名称为空
        public const int ERR_RoleNameSame = 200011;//角色名称相同
        public const int ERR_RoleNoExit = 200012;//角色角色不存在
        public const int Err_RequestSceneTypeError = 200013;
        public const int ERR_OtherAccountLogin = 200014;
        public const int ERR_SessionPlayerError = 200015;
        public const int ERR_NonePlayerError = 200016;
        public const int ERR_SessionStateError = 200017;
        public const int ERR_ReEnterGameError = 200018;
        public const int ERR_ReEnterGameError2 = 200019;
        public const int ERR_NumericTypeNoExit = 200020;
        public const int ERR_NumericTypeNoAddPoint = 200021;
        public const int ERR_AddPointNotEnough = 200022;
        public const int ERR_AlreadyAdventureState = 200023;
        public const int ERR_AdventureStateInDying = 200024;
        public const int ERR_AdventureErrorLevel = 200025;
        public const int ERR_AdventureLevelNotEnough = 200026;
        public const int ERR_AdventureRoundError = 200027;
        public const int ERR_AdventureWinResultError = 200028;
        public const int ERR_ExpNotEnough = 200029;
        public const int ERR_ExpNumError = 200030;
        public const int ERR_ItemNotExist = 200031;
        public const int ERR_AddBagItemError = 200032;
        public const int ERR_EquipItemError = 200032;
        public const int ERR_BagmaxLoadError = 200032;
        public const int ERR_MakeConfigNotExist = 200033;
        public const int ERR_ConsumNotEnough = 200034;
        public const int ERR_NoMakeFreeQueue = 200035;
        public const int ERR_NoMakeOverQueue = 200036;
        public const int ERR_NoTaskInfoExsit = 200037;
        public const int ERR_NoTaskCompleted = 200038;
        public const int ERR_BeforeTaskNoOver = 200039;
        public const int ERR_TaskRewarded = 200040;
        public const int ERR_ChatMessageEmpty = 200041;
    }
}