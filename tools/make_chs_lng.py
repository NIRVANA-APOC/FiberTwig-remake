#!/usr/bin/env python3
"""Generate remake/assets/lng/chs_105.lng - the Simplified Chinese interface.

The original localization scheme (see ../REVERSE_ENGINEERING.md) keeps every
caption of FiberTwig.li and applies ``lng/<code>_<id>.lng`` files that only
override widget properties (mostly Caption).  The shipped files are 8 bit
(CP1251/CP1252); this one is UTF-8 so the text can hold CJK characters - the
remake's loader detects the encoding and switches to the bundled CJK font.

Usage:
    python tools/make_chs_lng.py            # writes the .lng
    python tools/make_chs_lng.py --check    # report untranslated captions
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REMAKE = ROOT / "remake"
INTERFACE = REMAKE / "assets" / "data" / "interface.json"
OUT = REMAKE / "assets" / "lng" / "chs_105.lng"

# ---------------------------------------------------------------------------
# Translations.  Keys are the widget names of FiberTwig.li.  Numeric captions
# (score counters, radio 100 % ...) are intentionally not translated.
# ---------------------------------------------------------------------------
ZH: dict[str, str] = {
    # ---- title screen -----------------------------------------------------
    "BNewWTitle": "新游戏",
    "BLoadWTitle": "载入游戏",
    "BScoresWTitle": "最高分",
    "BQuitWTitle": "退出",
    "BOptionsWTitle": "选项",
    "BHelpWTitle": "帮助",
    "BDemoWLoad": "演示",
    # ---- "select starting bonus" dialog ----------------------------------
    "LSelectBonusWStartDialog": "选择初始奖励",
    "RHammerWStartDialog": "锤子（+5）",
    "RAmphoraWStartDialog": "双耳瓶（+5）",
    "RScoreWStartDialog": "分数（+200）",
    "LSelectDifficultyWStartDialog": "选择难度等级",
    "RNoLoseWStartDialog": "不会失败",
    "REasyWStartDialog": "简单",
    "RNormalWStartDialog": "普通",
    "RHardWStartDialog": "困难",
    "BBackWStartDialog": "返回",
    "BPlayWStartDialog": "开始",
    # ---- pause / confirmation menus --------------------------------------
    "BResumeWMenu": "继续游戏",
    "BAbortWMenu": "放弃关卡",
    "BHelpWMenu": "帮助",
    "BLoadWMenu": "载入游戏",
    "BOptionsWMenu": "选项",
    "BQuitWMenu": "退出",
    "LabelWAbortLivelDialog": "确定要放弃本关吗？",
    "BOkWAbortLivelDialog": "确定",
    "BCancelWAbortLivelDialog": "取消",
    "LabelWQuitGameDialog": "确定要退出游戏并放弃已获得的所有分数吗？",
    "BOkWQuitGameDialog": "确定",
    "BCancelWQuitGameDialog": "取消",
    "LabelWExitToMainMenu": "确定要返回主菜单吗？",
    "BOkWExitToMainMenu": "确定",
    "BCancelWExitToMainMenu": "取消",
    # ---- between level menu ----------------------------------------------
    "LLevelWBetweenLevelMenu": "关卡",
    "LScoreWBetweenLevelMenu": "分数：",
    "LExperienceWBetweenLevelMenu": "经验：",
    "BLoadWBetweenLevelMenu": "载入游戏",
    "BSaveWBetweenLevelMenu": "保存游戏",
    "BOptionsWBetweenLevelMenu": "选项",
    "BHelpWBetweenLevelMenu": "帮助",
    "BMainMenuWBetweenLevelMenu": "主菜单",
    "BNextLevelWBetweenLevelMenu": "下一关",
    "LLevelCompleteWFinishLevelDialog": "过关！",
    "BOkWFinishLevelDialog": "确定",
    # ---- load / save ------------------------------------------------------
    "LLoadWLoad": "载入存档",
    "LNameWLoad": "存档名称：",
    "BLoadWLoad": "载入",
    "BDeleteWLoad": "删除",
    "BCancelWLoad": "取消",
    "LSaveWSave": "保存存档",
    "LNameWSave": "存档名称：",
    "BSaveWSave": "保存",
    "BDeleteWSave": "删除",
    "BCancelWSave": "取消",
    "LabelWDeleteGameDialog": "确定要删除这个存档吗？",
    "BOkWDeleteGameDialog": "确定",
    "BCancelWDeleteGameDialog": "取消",
    "LabelWReplaceGameDialog": "已存在同名存档，确定要覆盖它吗？",
    "BOkWReplaceGameDialog": "确定",
    "BCancelWReplaceGameDialog": "取消",
    # ---- options ----------------------------------------------------------
    "LMusicWOptions": "音乐音量",
    "LSoundWOptions": "音效音量",
    "RNoMusicWOptions": "无音乐",
    "RNoSoundWOptions": "无音效",
    "CheckBoxHintsWOptions": "关闭提示",
    "CheckBoxColorWOptions": "32 位色彩",
    "CheckBoxFullScreenWOptions": "全屏",
    "BLanguageWOptions": "语言",
    "BOkWOptions": "确定",
    "BCancelWOptions": "取消",
    # ---- language dialog --------------------------------------------------
    "RENUWLanguage": "英语",
    "RDEUWLanguage": "德语",
    "RFRAWLanguage": "法语",
    "RPTBWLanguage": "葡萄牙语",
    "RRUSWLanguage": "俄语",
    "RCHSWLanguage": "简体中文",
    "BOkWLanguage": "确定",
    # ---- game over / finished / high scores -------------------------------
    "LabelWGameOverDialog": "游戏结束！再试一次吧……",
    "BOkWGameOverDialog": "确定",
    "LabelWGameFinishedDialog": "恭喜！您已完全通关 Fiber Twig！",
    "BOkWGameFinishedDialog": "确定",
    "LYourNameWGameFinishedDialog": "您的名字：",
    "LYourScoreWGameFinishedDialog": "本局得分：",
    "LYourHammerWGameFinishedDialog": "剩余锤子：",
    "LYourCapsWGameFinishedDialog": "剩余双耳瓶：",
    "LTotalScoreWGameFinishedDialog": "总分：",
    "LabelWHighScores": "最高分排行榜",
    "BOkWHighScores": "确定",
    "BClearWHighScores": "清空",
    "LabelWClearDialog": "确定要清空最高分记录吗？",
    "BOkWClearDialog": "确定",
    "BCancelWClearDialog": "取消",
    # ---- trial / registration --------------------------------------------
    "LNotEnabledWNotEnabled": (
        "希望您喜欢这款游戏！\n\n"
        "这是试用版本。您可以使用 14 天或运行 14 次（以先到者为准）。\n"
        "注册游戏后可解除所有限制，并开放全部关卡。详情请见"
    ),
    "BOkWNotEnabled": "以后再说",
    "BBuyNowWNotEnabled": "立即购买",
    "LLinksWNotEnabled": "www.puzzlelab.com",
    "LTrialThanksLabel": "感谢试玩！",
    "LTrialHopeLabel": "希望您喜欢！",
    "LTrialConditionLabel": (
        "这是试用版本。您可以使用 14 天或运行 14 次（以先到者为准）。"
        "注册游戏后可解除所有限制，并开放全部关卡。详情请见"
    ),
    "LTrialOrderLabel": "订购页面",
    "LTrialTimesLabel": "次",
    "LTrialDaysLabel": "天",
    "LTrialFiveMinutesLabel": "现在您只能再玩 5 分钟",
    "LTrialPlayButton": "开始",
    "LTrialQuitButton": "退出",
    "LTrialEnterKeyButton": "输入注册码",
    "LTrialRegistrationButton": "注册",
    "LTrialRegErrorLabel": "注册失败！",
    # ---- in-game HUD ------------------------------------------------------
    "BMenuWGame": "菜单",
    "LLevelWGame": "关卡：",
    "LScoreWGame": "分数：",
    "LDropSectionWGame": "丢弃区",
    "LLoadingWProgressBar": "载入中……",
    "LCombDoneWGame": "已完成组合！",
    # ---- level names (between level screen tabs) --------------------------
    "LLevel1WBetweenLevelMenu": "美丽女巫花园中的花丛间",
    "LLevel2WBetweenLevelMenu": "为鸟背上的女士谱写七音符旋律",
    "LLevel3WBetweenLevelMenu": "为追星者照亮前路",
    "LLevel4WBetweenLevelMenu": "解开智慧猫头鹰的谜题",
    "LLevel5WBetweenLevelMenu": "精灵乐师的常春藤花园",
    "LLevel6WBetweenLevelMenu": "为看门狗拼出骨头图案",
    "LLevel7WBetweenLevelMenu": "点亮半人马黑暗花园里的街灯",
    "LLevel8WBetweenLevelMenu": "绿发仙女的领地",
    "LLevel9WBetweenLevelMenu": "守护森林迷宫的老矮人",
    "LLevel10WBetweenLevelMenu": "与蘑菇玩捉迷藏",
    "LLevel11WBetweenLevelMenu": "拜访美丽的鹰身女妖",
    "LLevel12WBetweenLevelMenu": "觐见水下王国的统治者青蛙女王",
    "LLevel13WBetweenLevelMenu": "穿过魔术师花园里的茂密灌木",
    "LLevel14WBetweenLevelMenu": "半羊人美丽花园里的落花",
    "LLevel15WBetweenLevelMenu": "风之精灵在天空中欢唱",
    "LLevel16WBetweenLevelMenu": "巨型乌贼花园里的惊险冒险",
    "LLevel17WBetweenLevelMenu": "会见万物之主——飞天巨象",
    # ---- help: tab captions ----------------------------------------------
    "RIntroductionWHelp": "游戏介绍",
    "RGettingStartedWHelp": "新手上路",
    "RPlayingFieldWHelp": "游戏区域",
    "RHowToPlayWHelp": "玩法说明",
    "RArrangingTwigsWHelp": "摆放树枝",
    "RMagicToolsWHelp": "魔法工具",
    "RSkillsAndExperienceWHelp": "技能与经验",
    "RCombinationsWHelp": "组合",
    "RScoringPointsWHelp": "得分规则",
    "RKeyboardShortcutsWHelp": "快捷键",
    "ROptionsWHelp": "选项",
    "RBonusesWHelp": "奖励",
    "RRegistrationWHelp": "注册",
    "RAboutPuzzleLabWHelp": "关于 Puzzle Lab",
    "BCloseWHelp": "关闭",
    # ---- help: pages ------------------------------------------------------
    "LabelTIntroductionWHelp": (
        "在这款游戏中，您将置身于一座美丽的梦幻花园，这里居住着各种仙子生物。"
        "花园里曾用细小的树枝装饰出美丽的图案。一天，可怕的飓风袭来，摧毁了它们，"
        "花园昔日最迷人的景致所剩无几。您的任务就是连接树枝，恢复原来的图案。\n\n"
        "树枝会从屏幕底部缓缓经过并逐渐堆积。起始树枝已经在场地上，"
        "您需要连接一根与它匹配的树枝，再继续把树枝彼此相连，直到抵达屏幕顶端。"
        "所有树枝都必须连接起来，否则永远无法到达顶端。如果有树枝留有未连接的接口，"
        "您就无法向上推进，因为场地上的所有元素必须彼此连通。同时也要留意传送带，"
        "一旦它堆满，您就输了。\n\n"
        "有些关卡的场地上会出现一个物体，您需要用树枝把它缠绕进图案中。"
        "还有一些飞行的物体，会妨碍您放置树枝，请等它们飞过。"
        "魔法工具会在游戏中助您一臂之力——您可以用双耳瓶剪除多余的元素或生成所需形状的树枝，"
        "用锤子砸碎屏幕下方的树枝，防止传送带堆满。"
    ),
    "LabelTGettingStartedWHelp": (
        "游戏开始时，系统会请您选择初始奖励和难度等级。\n\n"
        "初始奖励可以选择：锤子、双耳瓶和额外分数。选择其中一种后，"
        "您将获得更多魔法工具或额外分数。\n\n"
        "选好初始奖励后，请选择游戏难度。您可以选择以下游戏模式：\n\n"
        "不会失败——永远不会输，但不会获得分数\n"
        "简单——树枝移动较慢，可以获得一些分数\n"
        "普通——树枝以正常速度出现，您的每个操作都能获得分数\n"
        "困难——树枝出现速度很快，可以获得更高分数"
    ),
    "LabelTPlayingFieldWHelp": (
        "游戏场地分为三部分。中央是恢复图案的区域。起始树枝已经给出，"
        "您需要连接另一根树枝，并一直延伸到顶端。\n\n"
        "屏幕下方是传送带，各种形状的树枝会逐渐出现在上面。"
        "当传送带没有空位时，游戏结束。您必须用这些树枝恢复原来的图案。\n\n"
        "右侧是信息面板和魔法工具。信息面板显示您的分数、当前关卡和“菜单”按钮。\n\n"
        "魔法工具双耳瓶和锤子能在游戏中帮上大忙。您可以用双耳瓶生成所需形状的树枝"
        "或剪除多余的元素，用锤子砸碎传送带上和场地上的树枝。"
        "工具下方是丢弃区，可以用来扔掉不需要的树枝。"
    ),
    "LabelTHowToPlayWHelp": (
        "游戏的基本规则如下：\n\n"
        "- 用鼠标左键点击您想使用的树枝。\n"
        "- 必要时点击鼠标右键旋转树枝。\n"
        "- 用鼠标左键点击场地，把树枝接到场地上的树枝上。\n"
        "- 让场地上的所有树枝彼此连接。\n"
        "- 将整组树枝连接到屏幕顶端。"
    ),
    "LabelTArrangingTwigsWHelp": (
        "树枝由屏幕下方的传送带运送。游戏目标是在场地上把树枝彼此连接起来，"
        "一直抵达屏幕顶端。传送带上的树枝会慢慢堆积，所以要留意不要让它堆满，"
        "否则游戏就会结束。除了普通树枝，还有两种特殊树枝："
        "神秘树枝——在拿起它之前您不知道它的形状；"
        "幸运树枝——使用它可以获得某些奖励。场地上还能看到透明树枝——"
        "您需要用相同形状的树枝覆盖它们。\n\n"
        "树枝有各种形状，接口数量也各不相同。当树枝有未连接的接口时，接口处会发光，"
        "表示可以在这里连接另一根树枝。下方的接口不能留空，"
        "因为只有所有树枝彼此连接，才能向上推进。"
        "妨碍您向上推进的未连接接口会用绿光标示。"
        "如果可以连接另一根树枝，您会看到绿色箭头；如果无法连接，则会看到红色叉号。"
    ),
    "LabelTMagicToolsWHelp": (
        "魔法工具能帮您通关。工具图标右上角的数字表示您还有多少个这种工具。"
        "某些奖励可以增加工具的使用次数。\n\n"
        "锤子。这个工具可以砸碎传送带上和场地上的树枝（初始树枝除外）。"
        "用锤子砸掉不符合图案的树枝，为新的树枝腾出空间。\n\n"
        "使用锤子：点击锤子图标将其选中。把锤子移到想要的树枝上，"
        "点击鼠标左键将其砸碎。您可以连续砸碎多根树枝。"
        "如果想放下锤子，点击鼠标右键即可。\n\n"
        "双耳瓶。您可能在两种情况下用到它：找不到所需形状的树枝时，"
        "以及需要剪除多余的元素时。\n\n"
        "使用双耳瓶：点击图标选中该工具。要生成缺少的树枝，"
        "请把双耳瓶移到场地上想要的位置，点击鼠标左键。"
        "要剪除多余的元素，请把双耳瓶移到想要的树枝上并点击。"
        "点击鼠标右键放下双耳瓶。"
    ),
    "LabelTSkillsAndExperienceWHelp": (
        "每关结束时，您都会获得一些经验点数。经验点数的多少取决于您上一关"
        "恢复图案所使用的树枝数量，以及完成的树枝组合数量"
        "（每个组合一点，如果完成了全部组合则再加两点）。\n\n"
        "您可以把经验点数分配到对话框左侧的五项技能上：\n\n"
        "时间控制——即使传送带已经堆满，也能让您在一段时间内不会失败。\n\n"
        "丢弃区加速器——让丢弃区工作得更快。\n\n"
        "好运——带来更多幸运树枝（带有奖励的树枝）。\n\n"
        "双耳瓶——生成所需形状的树枝并剪除多余的元素。\n\n"
        "锤子——砸碎传送带上和场地上多余的树枝。"
    ),
    "LabelTCombinationsWHelp": (
        "如果在恢复图案时完成特殊的树枝组合，您就能获得各种奖励。"
        "完成组合并不难：按照屏幕右侧图片所示的方式连接树枝即可。"
        "完成一个组合后，图片会消失，并出现新的组合图片让您用树枝去完成。"
    ),
    "LabelTScoringPointsWHelp": (
        "场地上的每根树枝都会为您赢得分数。每根树枝的分数取决于它拥有的接口数量，"
        "也就是说，接口越多的树枝得分越高。此外，"
        "完成树枝组合和使用奖励树枝获得的一些奖励也会带来额外分数。\n\n"
        "游戏中您还会获得经验点数。经验点数的多少取决于您恢复图案所使用的树枝数量，"
        "以及完成的树枝组合数量（每个组合一点，如果完成了全部组合则再加两点）。"
        "所以，尽量使用接口较多的树枝并完成树枝组合，您就能提升自己的技能。"
    ),
    "LabelTShortcutsWHelp": (
        "空格键——拿起传送带上的第一根树枝。如果传送带是空的，则会生成一根新树枝。\n"
        "“1”、“2”……“9”——拿起传送带上对应编号的树枝。\n"
        "F3——拿起（放下）锤子。\n"
        "F4——拿起（放下）双耳瓶。\n"
        "Del——扔掉选中的树枝。\n"
        "Esc——打开菜单。\n\n"
        "作弊码\n\n"
        "注册用户可以使用以下作弊码：\n\n"
        "1. _AddHammers——依次按 F5 F7 F7 F8 F6。使用次数：5 次。"
        "获得五把额外的锤子。每关最多使用五次。\n"
        "2. _AddAmphoras——依次按 F5 F6 F8 F7 F8。使用次数：5 次。"
        "获得五个额外的双耳瓶。每关最多使用五次。\n"
        "3. _ExplodeTwigs——依次按 F5 F8 F7 F6 F7 F8。使用次数：5 次。"
        "炸掉传送带上的所有树枝。每关最多使用五次。"
    ),
    "LabelTBonusesWHelp": (
        "完成树枝组合或使用奖励树枝时，您可能获得以下奖励：\n\n"
        "1. 爆炸炸弹——清空传送带，为新的树枝腾出空间。\n"
        "2. 额外锤子——给您一定数量的魔法锤子。\n"
        "3. 额外双耳瓶——给您一定数量的魔法双耳瓶。\n"
        "4. 额外分数——给您额外分数以提高得分。\n"
        "5. 丢弃区加速器——让树枝更快消失，以便扔掉更多树枝。\n"
        "6. 好运——让传送带上的所有树枝都带有奖励。\n"
        "7. 时间控制——临时奖励，传送带堆满时可以让您在一段时间内不会失败。"
    ),
    "LabelTOptionsWHelp": (
        "您可以调整以下游戏选项：\n\n"
        "语言——选择游戏语言\n"
        "关闭提示——如果不想看到提示，请勾选此项\n"
        "全屏——勾选此项以全屏模式游戏\n"
        "32 位色彩——勾选此项以显示真彩色\n"
        "音乐音量——调节音乐音量\n"
        "音效音量——调节音效音量"
    ),
    "LabelTRegistrationWHelp": (
        "这是试用版本。您可以使用 14 天或运行 14 次（以先到者为准）。"
        "注册游戏后可解除所有限制，并开放全部关卡。详情请访问：\n\n"
        "www.puzzlelab.com\n\n"
        "注册用户可获得以下好处：\n\n"
        "- 数小时的精彩游戏\n"
        "- 访问激动人心的新关卡\n"
        "- 更多可爱的生物\n"
        "- 丰富多样的树枝组合\n"
        "- 作弊码：_AddHammers、_AddAmphoras、_ExplodeTwigs"
    ),
    "LabelTAboutWHelp": (
        "致谢\n\n"
        "Puzzle Lab Studio 衷心感谢以下以各种方式为本项目做出贡献的人：\n\n"
        "Anastassia Fomina、Andrey Fomin、Pavel Moskvin、Oleg Ryabinin、"
        "Sophia Shishatskaya、Aleksei Fadeev、Dmitry Gorbatkov、Mikhail Tretyakov、"
        "Nadezhda Moskvina、Sergey Potapov、Sergey Zakharov、Anton Pishchour、"
        "Sergey Kaminsky、Olesya Derkach。"
    ),
    # ---- in-game hints ----------------------------------------------------
    "LHintSkillLive": "时间控制——即使传送带堆满，也能让您在一段时间内不会失败。",
    "LHintSkillDropAccel": "丢弃区加速器——让丢弃区工作得更快。",
    "LHintSkillLuckyTwig": "好运——带来更多幸运树枝（带有奖励的树枝）。",
    "LHintSkillAmphora": "双耳瓶——生成所需形状的树枝并剪除多余的元素。",
    "LHintSkillHammer": "锤子——砸碎传送带上和场地上多余的树枝。",
    "LHintClosedLink": "不能封闭图案，否则将无法连接所有树枝。",
    "LHintFirstTakeBonusFishka": "这是奖励树枝，使用它就能获得奖励。",
    "LHintFirstTakeQuestFishka": "这是神秘树枝，拿起之前不知道它的形状。",
    "LHintFirstTakeFishka": "将发光的接口对准相连，就能把树枝连接起来。",
    "LHintMatchingJoints": "只能连接接口相互匹配的树枝。",
    "LHintFirstTransparentFishka": "这是透明树枝，需要用相同形状的树枝覆盖它。",
    "LHintTransparentTwig": "需要用相同形状的树枝覆盖透明树枝。",
    "LHintLevelTop": "现在连接所有树枝，恢复图案并完成关卡。",
    "LHintFishComb": "您完成了一个树枝组合，获得了奖励。",
}


def load_captions() -> dict[str, str]:
    data = json.loads(INTERFACE.read_text(encoding="utf-8"))
    return {n["Name"]: str(n.get("Caption", "")) for n in data["nodes"] if n.get("Caption")}


def missing(captions: dict[str, str]) -> list[str]:
    """Captions that contain a letter but have no Chinese translation."""
    out = []
    for name, cap in captions.items():
        if not re.search(r"[A-Za-z]", cap):
            continue
        if name not in ZH:
            out.append(name)
    return sorted(out)


def xml_escape(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def build() -> str:
    data = json.loads(INTERFACE.read_text(encoding="utf-8"))
    classes = {n["Name"]: n["Class"] for n in data["nodes"]}
    parts = ['<?xml version="1.0" encoding="UTF-8"?>', "<LabInterface>"]
    for name in sorted(ZH):
        cls = classes.get(name, "TLabLabel")
        parts.append(f'\t<o c="{cls}">')
        parts.append(f"\t\t<p n=\"Name\">{name}</p>")
        parts.append("\t\t<p n=\"CharSet\">CHINESE</p>")
        parts.append(f'\t\t<p n="Caption">{xml_escape(ZH[name])}</p>')
        parts.append("\t</o>")
    parts.append("</LabInterface>")
    return "\n".join(parts) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="only report missing translations")
    args = ap.parse_args()
    caps = load_captions()
    miss = missing(caps)
    if miss:
        print(f"{len(miss)} caption(s) without a Chinese translation:")
        for name in miss:
            print(f"  {name}: {caps[name][:70]!r}")
    else:
        print("all textual captions are translated")
    if args.check:
        return 1 if miss else 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build(), encoding="utf-8", newline="\n")
    chars = {c for v in ZH.values() for c in v}
    print(f"wrote {OUT.relative_to(ROOT)} ({len(ZH)} widgets, {len(chars)} distinct characters)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
