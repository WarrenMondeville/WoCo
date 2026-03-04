namespace ET.Client
{
    [Event(SceneType.LockStep)]
    public class LSSceneInitFinish_RemoveUI : AEvent<Scene, LSSceneInitFinish>
    {
        protected override async ETTask Run(Scene scene, LSSceneInitFinish args)
        {
            await UIHelper.Remove(scene, UIType.UILSLobby);
        }
    }
}
