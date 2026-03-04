namespace ET.Client
{
    [Event(SceneType.LockStep)]
    public class LSSceneChangeStart_CreateUI : AEvent<Scene, LSSceneChangeStart>
    {
        protected override async ETTask Run(Scene root, LSSceneChangeStart args)
        {
            await UIHelper.Create(root, UIType.UILSRoom, UILayer.Low);
        }
    }
}
