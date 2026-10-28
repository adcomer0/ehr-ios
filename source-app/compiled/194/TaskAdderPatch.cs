using AmongUs.GameOptions;
using HarmonyLib;
using UnityEngine;

namespace EHR;

[HarmonyPatch(typeof(TaskAdderGame), "ShowFolder")]
internal static class ShowFolderPatch
{
    private static TaskFolder CustomRolesFolder;

    public static void Prefix(TaskAdderGame __instance, [HarmonyArgument(0)] TaskFolder taskFolder)
    {
        if (__instance.Root == taskFolder && CustomRolesFolder == null)
        {
            TaskFolder rolesFolder = Object.Instantiate(
                __instance.RootFolderPrefab,
                __instance.transform
            );

            rolesFolder.gameObject.SetActive(false);
            rolesFolder.FolderName = Main.ModName;
            CustomRolesFolder = rolesFolder;
            __instance.Root.SubFolders.Add(rolesFolder);
        }
    }

    public static void Postfix(TaskAdderGame __instance, [HarmonyArgument(0)] TaskFolder taskFolder)
    {
        Logger.Info("Opened " + taskFolder.FolderName, "TaskFolder");
        var xCursor = 0f;
        var yCursor = 0f;
        var maxHeight = 0f;

        if (CustomRolesFolder != null && CustomRolesFolder.FolderName == taskFolder.FolderName)
        {
            CustomRoles[] list = Main.CustomRoleValues;

            foreach (CustomRoles cRoleID in list)
            {
                TaskAddButton button = Object.Instantiate(__instance.RoleButton);
                button.Text.text = Utils.GetRoleName(cRoleID);
                __instance.AddFileAsChild(CustomRolesFolder, button, ref xCursor, ref yCursor, ref maxHeight);
                
                var roleBehaviour = button.gameObject.AddComponent<RoleBehaviour>();
                roleBehaviour.Role = (RoleTypes)cRoleID + 1000;

                button.Role = roleBehaviour;

                Color roleColor = Utils.GetRoleColor(cRoleID);

                button.FileImage.color = roleColor;
                button.RolloverHandler.OutColor = roleColor;
                button.RolloverHandler.OverColor = new(roleColor.r * 0.5f, roleColor.g * 0.5f, roleColor.b * 0.5f);
            }
        }
    }

    internal static void __EHRStaticCallback_317(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        TaskAdderGame __ehrp0 = __ehrFrame.GetInstance<TaskAdderGame>();
        TaskFolder __ehrp1 = __ehrFrame.GetArgument<TaskFolder>(0);
        try
        {
            Prefix(__ehrp0, __ehrp1);
        }
        finally
        {
        }
    }


    internal static void __EHRStaticCallback_318(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        TaskAdderGame __ehrp0 = __ehrFrame.GetInstance<TaskAdderGame>();
        TaskFolder __ehrp1 = __ehrFrame.GetArgument<TaskFolder>(0);
        try
        {
            Postfix(__ehrp0, __ehrp1);
        }
        finally
        {
        }
    }

}

[HarmonyPatch(typeof(TaskAddButton), "Update")]
internal class TaskAddButtonUpdatePatch
{
    public static bool Prefix(TaskAddButton __instance)
    {
        try
        {
            if ((int)__instance.Role.Role >= 1000)
            {
                CustomRoles playerCustomRole = PlayerControl.LocalPlayer.GetCustomRole();
                CustomRoles fileCustomRole = (CustomRoles)__instance.Role.Role - 1000;
                __instance.Overlay.enabled = playerCustomRole == fileCustomRole;
            }
        }
        catch { }

        return true;
    }

    internal static void __EHRStaticCallback_319(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        TaskAddButton __ehrp0 = __ehrFrame.GetInstance<TaskAddButton>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = Prefix(__ehrp0);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}

[HarmonyPatch(typeof(TaskAddButton), "AddTask")]
internal static class AddTaskButtonPatch
{
    public static bool Prefix(TaskAddButton __instance)
    {
        try
        {
            if ((int)__instance.Role.Role >= 1000)
            {
                CustomRoles FileCustomRole = (CustomRoles)__instance.Role.Role - 1000;
                PlayerControl.LocalPlayer.RpcSetCustomRole(FileCustomRole);
                PlayerControl.LocalPlayer.RpcSetRole(FileCustomRole.GetRoleTypes(), true);
                return false;
            }
        }
        catch { }

        return true;
    }

    internal static void __EHRStaticCallback_320(global::EHR.EHRStaticPatchFrame __ehrFrame)
    {
        TaskAddButton __ehrp0 = __ehrFrame.GetInstance<TaskAddButton>();
        bool __ehrReturn = default;
        try
        {
            __ehrReturn = Prefix(__ehrp0);
        }
        finally
        {
        }
        __ehrFrame.RunOriginal = __ehrFrame.RunOriginal && __ehrReturn;
    }

}