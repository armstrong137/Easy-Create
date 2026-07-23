/// 星球（小说）相关常量：可用纹理集合、循环分配、数量上限。
///
/// 放在 core 层，供表现层与数据层共用（数据层不能 import 表现层）。
library;

/// 可用的行星纹理名，共 5 张贴纸素材。
/// 新建星球按位置循环分配：第 6 颗起重复 earth→mars→…（五个一组循环），
/// 不再复制上一颗（历史 bug：靠异步流长度取模，快速连建会重复土星）。
const kPlanetTextures = ['earth', 'mars', 'jupiter', 'venus', 'saturn'];

/// 星球数量上限（用户定稿：最多 30 颗）。
const kMaxNovels = 30;

/// 第 [index] 颗星球（0 基）应用的纹理名——五个一组循环。
String planetForIndex(int index) =>
    kPlanetTextures[index % kPlanetTextures.length];
