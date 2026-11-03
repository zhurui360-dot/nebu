import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'lang.dart';

/// 界面文案表。每行 = 一条文案，7 列按 [AppLang] 顺序排列：
/// 简体中文 / 繁體中文 / English / 日本語 / 한국어 / བོད་ཡིག / ئۇيغۇرچە
///
/// 藏语、维吾尔语留空（''）的条目会回退英文，再回退简体中文，
/// 这样长尾文案不会出现空白，也方便后续逐条补齐翻译。
const Map<String, List<String>> _dict = {
  // ---------- 底部导航 ----------
  'tab.home': ['首页', '首頁', 'Home', 'ホーム', '홈', 'མདུན་ངོས།', 'باش بەت'],
  'tab.browse': [
    '浏览',
    '瀏覽',
    'Browse',
    'ライブラリ',
    '라이브러리',
    'དཔེ་མཛོད།',
    'كىتابخانا'
  ],
  'tab.search': [
    '搜索',
    '搜尋',
    'Search',
    '検索',
    '검색',
    'བཤེར་འཚོལ།',
    'ئىزدەش'
  ],
  'tab.me': ['我的', '我的', 'Me', 'マイ', '마이', 'ང་', 'مەن'],

  // ---------- 通用 ----------
  'ok': ['确定', '確定', 'OK', 'OK', '확인', 'འགྲིག', 'جەزملەش'],
  'cancel': [
    '取消',
    '取消',
    'Cancel',
    'キャンセル',
    '취소',
    'ཕྱིར་འཐེན།',
    'بىكار قىلىش'
  ],
  'delete': ['删除', '刪除', 'Delete', '削除', '삭제', 'བསུབས།', 'ئۆچۈرۈش'],
  'save': ['保存', '儲存', 'Save', '保存', '저장', 'ཉར་ཚགས།', 'ساقلاش'],
  'close': ['关闭', '關閉', 'Close', '閉じる', '닫기', 'ཁ་རྒྱག', 'تاقاش'],
  'done': ['完成', '完成', 'Done', '完了', '완료', 'ལེགས་སོང་།', 'تامام'],
  'retry': ['重试', '重試', 'Retry', '再試行', '다시 시도', 'བསྐྱར་ཚོད།', 'قايتا سىناش'],
  'more': ['更多', '更多', 'More', 'もっと見る', '더보기', '', 'تېخىمۇ كۆپ'],
  'all': ['全部', '全部', 'All', 'すべて', '전체', 'ཚང་མ།', 'ھەممىسى'],
  'play': ['播放', '播放', 'Play', '再生', '재생', 'གཏོང་བ།', 'قويۇش'],
  'pause': ['暂停', '暫停', 'Pause', '一時停止', '일시정지', 'གནས་འཇོག', 'توختىتىش'],
  'next': ['下一首', '下一首', 'Next', '次の曲', '다음 곡', '', 'كېيىنكى ناخشا'],
  'gotIt': ['知道了', '知道了', 'Got it', '了解', '확인', '', 'چۈشەندىم'],

  // ---------- 单位 ----------
  'unit.songs': ['{n} 首', '{n} 首', '{n} songs', '{n} 曲', '{n} 곡', '{n} གླུ་གཞས།', '{n} ناخشا'],
  'unit.albums': ['{n} 张专辑', '{n} 張專輯', '{n} albums', '{n} アルバム', '{n} 앨범', '', '{n} ئالبوم'],
  'unit.artists': ['{n} 位歌手', '{n} 位歌手', '{n} artists', '{n} アーティスト', '{n} 아티스트', '', ''],
  'unit.folders': ['{n} 个目录', '{n} 個目錄', '{n} folders', '{n} フォルダ', '{n} 폴더', '', '{n} مۇندەرىجە'],
  'unit.playlists': ['{n} 个歌单', '{n} 個歌單', '{n} playlists', '{n} プレイリスト', '{n} 플레이리스트', '', ''],

  // ---------- 首页 ----------
  'home.myMusic': ['我的音乐', '我的音樂', 'My music', 'マイミュージック', '내 음악', 'ངའི་གླུ་གཞས།', 'مېنىڭ مۇزىكام'],
  'home.recent': ['最近播放', '最近播放', 'Recently played', '最近再生', '최근 재생', '', 'يېقىندا قويۇلغان'],
  'home.favorites': ['我的收藏', '我的收藏', 'Favorites', 'お気に入り', '즐겨찾기', 'དགའ་མོས།', 'ياقتۇرغانلىرىم'],
  'home.playlists': ['歌单', '歌單', 'Playlists', 'プレイリスト', '플레이리스트', '', 'قويۇش تىزىملىكى'],
  'home.nowPlaying': ['正在播放', '正在播放', 'Now playing', '再生中', '재생 중', '', 'قويۇلۇۋاتىدۇ'],
  'home.resume': ['继续播放', '繼續播放', 'Continue', '続きを再生', '이어서 재생', '', 'داۋاملاشتۇرۇش'],
  'home.empty': ['还没有音乐', '還沒有音樂', 'No music yet', '音楽がありません', '음악이 없습니다', '', 'مۇزىكا يوق'],
  'home.emptySub': [
    '连接你的 WebDAV，选一个音乐目录导入，\n歌就会出现在这里。',
    '連接你的 WebDAV，選一個音樂目錄匯入，\n歌就會出現在這裡。',
    'Connect your WebDAV, pick a music folder,\nand your songs will show up here.',
    'WebDAV に接続して音楽フォルダを取り込むと、\nここに曲が表示されます。',
    'WebDAV를 연결하고 음악 폴더를 가져오면\n여기에 곡이 표시됩니다.',
    '',
    ''
  ],
  'home.cached': ['已缓存', '已快取', 'Cached', 'キャッシュ済み', '캐시됨', '', 'غەملەنگەن'],
  'home.howTo': ['怎么用', '怎麼用', 'How to use', '使い方', '사용법', '', 'قانداق ئىشلىتىش'],
  'home.connectCloud': ['去连接网盘', '去連接網盤', 'Connect storage', 'クラウドに接続', '클라우드 연결', '', 'تور دىسكىغا ئۇلاش'],
  'home.step1': [
    '在网盘源里填 WebDAV 地址、账号与应用密码',
    '在網盤源裡填 WebDAV 位址、帳號與應用密碼',
    'Enter your WebDAV address, account and app password',
    'WebDAV のアドレス・アカウント・アプリパスワードを入力します',
    'WebDAV 주소, 계정, 앱 비밀번호를 입력합니다',
    '',
    ''
  ],
  'home.step2': [
    '勾选音乐目录，等待扫描并读取标签',
    '勾選音樂目錄，等待掃描並讀取標籤',
    'Pick a music folder and let it scan the tags',
    '音楽フォルダを選ぶと、スキャンしてタグを読み取ります',
    '음악 폴더를 선택하면 스캔 후 태그를 읽습니다',
    '',
    ''
  ],
  'home.step3': [
    '回到首页即可播放；同名 .lrc 会自动识别为歌词',
    '回到首頁即可播放；同名 .lrc 會自動識別為歌詞',
    'Play from Home — a matching .lrc becomes the lyrics automatically',
    'ホームから再生できます。同名の .lrc は自動で歌詞になります',
    '홈에서 재생하세요. 같은 이름의 .lrc는 자동으로 가사가 됩니다',
    '',
    ''
  ],

  // ---------- 音乐库 ----------
  'lib.title': ['音乐库', '音樂庫', 'Library', 'ライブラリ', '라이브러리', 'དཔེ་མཛོད།', 'كىتابخانا'],
  'lib.allSongs': ['全部歌曲', '全部歌曲', 'All songs', 'すべての曲', '전체 곡', 'གླུ་གཞས་ཚང་མ།', 'بارلىق ناخشىلار'],
  'lib.albums': ['专辑', '專輯', 'Albums', 'アルバム', '앨범', 'གླུ་སྒྲིག', 'ئالبوم'],
  'lib.artists': ['歌手', '歌手', 'Artists', 'アーティスト', '아티스트', 'གླུ་མཁན།', 'ئىجراچى'],
  'lib.favorites': ['我喜欢', '我喜歡', 'Liked', 'お気に入り', '좋아하는 곡', 'དགའ་མོས།', 'ياقتۇرغان'],
  'lib.recentAdded': ['最近添加', '最近加入', 'Recently added', '最近追加', '최근 추가', '', 'يېقىندا قوشۇلغان'],
  'lib.downloads': ['下载列表', '下載清單', 'Downloads', 'ダウンロード', '다운로드', 'ཕབ་ལེན།', 'چۈشۈرۈش'],
  'lib.collections': ['收藏', '收藏', 'Collections', 'コレクション', '컬렉션', 'དགའ་མོས།', 'توپلام'],
  'lib.favAlbums': ['收藏的专辑', '收藏的專輯', 'Saved albums', 'お気に入りアルバム', '즐겨찾는 앨범', '', ''],
  'lib.myPlaylists': ['自建歌单', '自建歌單', 'My playlists', '作成したプレイリスト', '내 플레이리스트', '', ''],
  'lib.edit': ['编辑', '編輯', 'Edit', '編集', '편집', '', 'تەھرىرلەش'],
  'lib.empty': ['音乐库是空的', '音樂庫是空的', 'Your library is empty', 'ライブラリは空です', '라이브러리가 비어 있습니다', '', 'كىتابخانا قۇرۇق'],
  'lib.emptySub': [
    '导入网盘目录后，这里会按歌手、专辑、歌单自动归类',
    '匯入網盤目錄後，這裡會按歌手、專輯、歌單自動歸類',
    'Import a folder and everything is grouped by artist, album and playlist.',
    'フォルダを取り込むと、アーティスト・アルバム・プレイリスト別に整理されます。',
    '폴더를 가져오면 아티스트, 앨범, 플레이리스트별로 정리됩니다.',
    '',
    ''
  ],
  'lib.goImport': ['去导入目录', '去匯入目錄', 'Import a folder', 'フォルダを取り込む', '폴더 가져오기', '', ''],
  'lib.mine': ['我的', '我的', 'Mine', 'マイ', '내 항목', '', 'مېنىڭ'],
  'lib.favSub': ['{n} 首已收藏的歌', '{n} 首已收藏的歌', '{n} liked songs', 'お気に入り {n} 曲', '좋아하는 곡 {n}개', '', ''],
  'lib.byTime': ['按时间倒序', '按時間倒序', 'Newest first', '新しい順', '최신순', '', ''],
  'lib.downloadsSub': ['已缓存到本地，断网也能播', '已快取到本地，斷網也能播', 'Cached locally, plays offline', 'ローカルに保存済み。オフライン再生可', '로컬에 저장됨. 오프라인 재생 가능', '', ''],
  'lib.allHidden': ['这一块都藏起来了 · 点这里挑回来', '這一塊都藏起來了 · 點這裡挑回來', 'Everything here is hidden — tap to bring it back', 'ここはすべて非表示です。タップして戻す', '모두 숨겨졌습니다. 탭하여 복원', '', ''],
  'lib.importedDirs': [
    '{n} 个目录已导入',
    '{n} 個目錄已匯入',
    '{n} folders imported',
    '{n} フォルダを取り込み済み',
    '{n}개 폴더 가져옴',
    '',
    ''
  ],

  // ---------- 搜索 ----------
  'search.hint': ['搜索歌曲、专辑、歌手', '搜尋歌曲、專輯、歌手', 'Search songs, albums, artists', '曲・アルバム・アーティストを検索', '곡, 앨범, 아티스트 검색', '', 'ناخشا، ئالبوم، ئىجراچى ئىزدەش'],
  'search.recent': ['最近搜索', '最近搜尋', 'Recent searches', '最近の検索', '최근 검색어', '', 'يېقىنقى ئىزدەش'],
  'search.clear': ['清空', '清空', 'Clear', 'クリア', '지우기', '', 'تازىلاش'],
  'search.songs': ['歌曲', '歌曲', 'Songs', '曲', '곡', 'གླུ་གཞས།', 'ناخشا'],
  'search.empty': ['换个关键词试试', '換個關鍵詞試試', 'Try another keyword', '別のキーワードを試してください', '다른 검색어를 입력해 보세요', '', ''],
  'search.cached': ['离线缓存', '離線快取', 'Offline cache', 'オフラインキャッシュ', '오프라인 캐시', '', 'تورسىز غەملەك'],
  'search.hits': ['命中 {n} 个结果', '命中 {n} 個結果', '{n} results', '{n} 件ヒット', '{n}개 결과', '', ''],
  'search.byRelevance': ['按相关度', '依相關度', 'By relevance', '関連度順', '관련도순', '', ''],
  'search.noHistory': ['还没有搜索记录，试着搜个歌名或歌手', '還沒有搜尋記錄，試著搜個歌名或歌手', 'No searches yet — try a song or artist', '検索履歴はありません。曲名やアーティストで検索してみてください', '검색 기록이 없습니다. 곡명이나 아티스트를 검색해 보세요', '', ''],

  // ---------- 播放页 ----------
  'player.addToPlaylist': ['加入歌单', '加入歌單', 'Add to playlist', 'プレイリストに追加', '플레이리스트에 추가', '', 'تىزىملىككە قوشۇش'],
  'player.viewAlbum': ['查看专辑', '查看專輯', 'View album', 'アルバムを見る', '앨범 보기', '', 'ئالبومنى كۆرۈش'],
  'player.viewArtist': ['查看歌手', '查看歌手', 'View artist', 'アーティストを見る', '아티스트 보기', '', 'ئىجراچىنى كۆرۈش'],
  'player.noLyric': ['这首还没有歌词', '這首還沒有歌詞', 'No lyrics for this song yet', 'この曲の歌詞はまだありません', '아직 가사가 없습니다', '', 'بۇ ناخشىنىڭ تېكىستى يوق'],
  'player.showTrans': ['显示翻译', '顯示翻譯', 'Show translation', '翻訳を表示', '번역 보기', '', 'تەرجىمىنى كۆرسىتىش'],
  'player.hideTrans': ['隐藏翻译', '隱藏翻譯', 'Hide translation', '翻訳を隠す', '번역 숨기기', '', 'تەرجىمىنى يوشۇرۇش'],
  'player.fillMeta': ['补全歌词与封面', '補全歌詞與封面', 'Fetch lyrics & cover', '歌詞とカバーを取得', '가사 및 커버 가져오기', '', ''],
  'player.preview': ['当前是无声预览', '目前是無聲預覽', 'Silent preview', '無音プレビュー', '무음 미리보기', '', ''],
  'player.lrcHint': [
    '把同名 .lrc 放到歌曲同目录，重新导入即可显示',
    '把同名 .lrc 放到歌曲同目錄，重新匯入即可顯示',
    'Put a matching .lrc next to the song, then re-import',
    '同名の .lrc を曲と同じ場所に置き、再取り込みしてください',
    '같은 이름의 .lrc를 곡과 같은 폴더에 두고 다시 가져오세요',
    '',
    ''
  ],
  'player.playMode': ['播放模式：{m}', '播放模式：{m}', 'Play mode: {m}', '再生モード：{m}', '재생 모드: {m}', '', ''],
  'player.playModeHint': ['点这里或底部循环键切换', '點這裡或底部循環鍵切換', 'Tap here or the loop button below', 'ここか下部のループボタンで切替', '여기 또는 아래 반복 버튼으로 전환', '', ''],
  'player.fillMetaSub': ['用公开源在线查找', '用公開源線上查找', 'Look up public sources online', '公開ソースから取得', '공개 소스에서 검색', '', ''],
  'player.intoPlaylist': ['收进你的歌单', '收進你的歌單', 'Save it into a playlist', 'プレイリストに入れる', '플레이리스트에 담기', '', ''],
  'player.cover': ['看封面', '看封面', 'Cover', 'カバーを見る', '커버 보기', '', ''],

  // ---------- 我的 ----------
  'me.title': ['我的', '我的', 'Me', 'マイ', '마이', 'ང་', 'مەن'],
  'me.foldersIndexed': [
    '{a} 个目录 · {b} 首已索引',
    '{a} 個目錄 · {b} 首已索引',
    '{a} folders · {b} indexed',
    '{a} フォルダ · {b} 曲を登録済み',
    '{a}개 폴더 · {b}곡 색인됨',
    '',
    ''
  ],
  'me.groupPlay': ['播放', '播放', 'Playback', '再生', '재생', '', 'قويۇش'],
  'me.cacheLimit': ['边听边缓存', '邊聽邊快取', 'Cache while playing', '再生中にキャッシュ', '재생 중 캐시', '', 'قويۇۋاتقاندا غەملەش'],
  'me.cacheLimitSub': ['点这里修改缓存大小上限', '點這裡修改快取大小上限', 'Tap to change the cache size limit', 'タップしてキャッシュ上限を変更', '탭하여 캐시 한도 변경', '', ''],
  'me.clearAudio': ['清除边听缓存', '清除邊聽快取', 'Clear play cache', '再生キャッシュを削除', '재생 캐시 지우기', '', ''],
  'me.clearAudioSub': [
    '播放时自动缓存下来的音频（断网可播），清了不影响曲库',
    '播放時自動快取下來的音訊（斷網可播），清了不影響音樂庫',
    'Audio cached during playback (plays offline). Clearing it keeps your library.',
    '再生中に自動保存された音声（オフライン再生用）。削除してもライブラリは残ります。',
    '재생 중 자동 저장된 오디오(오프라인 재생용). 삭제해도 라이브러리는 유지됩니다.',
    '',
    ''
  ],
  'me.clearData': ['清除缓存数据', '清除快取資料', 'Clear cached data', 'キャッシュデータを削除', '캐시 데이터 지우기', '', ''],
  'me.clearDataSub': [
    '清空曲库并删掉封面、歌词与离线缓存（保留已添加的目录）',
    '清空音樂庫並刪掉封面、歌詞與離線快取（保留已加入的目錄）',
    'Empty the library and delete covers, lyrics and offline cache. Added folders are kept.',
    'ライブラリを空にし、カバー・歌詞・オフラインキャッシュを削除します（追加済みフォルダは保持）。',
    '라이브러리를 비우고 커버, 가사, 오프라인 캐시를 삭제합니다(추가한 폴더는 유지).',
    '',
    ''
  ],
  'me.groupLibrary': ['音乐库', '音樂庫', 'Library', 'ライブラリ', '라이브러리', 'དཔེ་མཛོད།', 'كىتابخانا'],
  'me.onlineMeta': ['在线补全歌词与封面', '線上補全歌詞與封面', 'Fetch lyrics & covers online', '歌詞とカバーをオンライン取得', '가사 및 커버 온라인 가져오기', '', ''],
  'me.onlineMetaSub': [
    '导入后自动进行：先读内嵌，没有才联网补',
    '匯入後自動進行：先讀內嵌，沒有才連網補',
    'Runs after import: embedded tags first, online only as fallback.',
    '取り込み後に自動実行：まず埋め込み情報、なければオンラインで補完。',
    '가져온 후 자동 실행: 내장 정보 우선, 없으면 온라인에서 보완.',
    '',
    ''
  ],
  'me.metaSources': ['歌词源 / 封面源', '歌詞源 / 封面源', 'Lyrics & cover sources', '歌詞・カバー取得元', '가사 / 커버 소스', '', ''],
  'me.manage': ['管理', '管理', 'Manage', '管理', '관리', '', 'باشقۇرۇش'],
  'me.filenameRule': ['按文件名识别', '按檔名識別', 'Read from filename', 'ファイル名から判定', '파일명으로 인식', '', ''],
  'me.filenameAuto': ['智能', '智慧', 'Auto', '自動', '자동', 'རང་འགུལ།', 'ئاپتوماتىك'],
  'me.filenameCustom': ['自定义', '自訂', 'Custom', 'カスタム', '사용자 지정', '', 'ئۆزلۈكىدىن'],
  'me.groupAppearance': ['外观', '外觀', 'Appearance', '外観', '화면', 'མཐོང་སྣང་།', 'كۆرۈنۈش'],
  'me.theme': ['主题', '主題', 'Theme', 'テーマ', '테마', 'བརྗོད་གཞི།', 'تېما'],
  'me.themeAuto': ['自动', '自動', 'Auto', '自動', '자동', 'རང་འགུལ།', 'ئاپتوماتىك'],
  'me.themeLight': ['浅色', '淺色', 'Light', 'ライト', '라이트', 'དཀར་པོ།', 'يورۇق'],
  'me.themeDark': ['深色', '深色', 'Dark', 'ダーク', '다크', 'ནག་པོ།', 'قاراڭغۇ'],
  'me.language': ['语言', '語言', 'Language', '言語', '언어', 'སྐད་ཡིག', 'تىل'],
  'me.languageSub': ['界面语言，默认跟随系统', '介面語言，預設跟隨系統', 'Interface language, follows your system by default', '表示言語（初期値はシステムに従う）', '인터페이스 언어(기본값: 시스템)', '', ''],
  'me.groupStorage': ['下载与存储', '下載與儲存', 'Downloads & storage', 'ダウンロードと保存', '다운로드 및 저장', '', 'چۈشۈرۈش ۋە ساقلاش'],
  'me.saveDir': ['音乐保存目录', '音樂儲存目錄', 'Music folder', '音楽の保存先', '음악 저장 위치', 'རོལ་དབྱངས་ཉར་ས།', 'مۇزىكا ساقلاش مۇندەرىجىسى'],
  'me.saveDirSub': ['下载到本地时保存到这里', '下載到本地時儲存到這裡', 'Where downloaded songs are saved', 'ダウンロードした曲の保存先', '다운로드한 곡의 저장 위치', '', ''],
  'me.groupAbout': ['关于', '關於', 'About', 'このアプリについて', '정보', '', 'ھەققىدە'],
  'me.version': ['当前版本', '目前版本', 'Version', 'バージョン', '버전', '', 'نەشرى'],
  'me.checkUpdate': ['检查更新', '檢查更新', 'Check for updates', 'アップデートを確認', '업데이트 확인', '', 'يېڭىلاشنى تەكشۈرۈش'],
  'me.newVersion': ['发现新版本', '發現新版本', 'New version', '新しいバージョン', '새 버전', '', 'يېڭى نەشرى'],
  'me.upToDate': ['已经是最新版 {v}，没有可更新的版本', '已經是最新版 {v}，沒有可更新的版本', 'You are on the latest version {v}', '最新バージョン {v} です', '최신 버전 {v} 입니다', '', ''],
  'me.foundTag': ['可更新', '可更新', 'Update', '更新あり', '업데이트', '', 'يېڭىلاش'],

  // ---------- 我的音乐 ----------
  'mymusic.empty': ['还没有导入目录', '還沒有匯入目錄', 'No folders yet', 'フォルダがありません', '폴더가 없습니다', '', 'مۇندەرىجە يوق'],
  'mymusic.addManage': ['添加目录 / 管理音乐来源', '加入目錄 / 管理音樂來源', 'Add folder / manage sources', 'フォルダ追加 / 取得元管理', '폴더 추가 / 소스 관리', '', ''],
  'mymusic.scan': ['扫描音乐', '掃描音樂', 'Scan for music', '音楽をスキャン', '음악 스캔', 'རོལ་དབྱངས་སྒྲིག', 'مۇزىكا سكانلاش'],
  'mymusic.scanning': ['扫描中 {p}%', '掃描中 {p}%', 'Scanning {p}%', 'スキャン中 {p}%', '스캔 중 {p}%', '', ''],
  'mymusic.scanDone': ['扫描完成：新增 {n} 首', '掃描完成：新增 {n} 首', 'Scan complete: {n} new songs', 'スキャン完了：{n} 曲追加', '스캔 완료: {n}곡 추가', '', ''],
  'mymusic.noFolderToScan': ['还没有可扫描的目录', '還沒有可掃描的目錄', 'No folder to scan yet', 'スキャンするフォルダがありません', '스캔할 폴더가 없습니다', '', ''],
  'mymusic.emptyRow': [
    '还没有添加目录，点下面「添加目录」开始',
    '還沒有加入目錄，點下面「加入目錄」開始',
    'No folder yet — tap "Add folder" below',
    'フォルダがありません。下の「フォルダ追加」から始めましょう',
    '폴더가 없습니다. 아래 "폴더 추가"를 누르세요',
    '',
    ''
  ],
  'mymusic.busy': ['正在扫描中，请稍候', '正在掃描中，請稍候', 'Scanning, please wait', 'スキャン中です。お待ちください', '스캔 중입니다. 잠시만요', '', ''],
  'mymusic.scanStart': ['开始扫描 {n} 个目录…', '開始掃描 {n} 個目錄…', 'Scanning {n} folders…', '{n} フォルダをスキャン中…', '{n}개 폴더 스캔 중…', '', ''],
  'mymusic.scanNoNew': ['扫描完成，没有新歌', '掃描完成，沒有新歌', 'Scan complete, nothing new', 'スキャン完了。新しい曲はありません', '스캔 완료, 새 곡 없음', '', ''],
  'mymusic.scanRunning': ['已开始扫描，新歌会自动加入', '已開始掃描，新歌會自動加入', 'Scan started — new songs will be added automatically', 'スキャンを開始しました。新しい曲は自動で追加されます', '스캔을 시작했습니다. 새 곡은 자동으로 추가됩니다', '', ''],
  'src.localShort': ['本地', '本地', 'Local', 'ローカル', '로컬', '', 'يەرلىك'],
  'src.cloudShort': ['网盘', '網盤', 'Cloud', 'クラウド', '클라우드', '', 'تور دىسكىسى'],
  'unit.files': ['{n} 个文件', '{n} 個檔案', '{n} files', '{n} ファイル', '{n}개 파일', '', '{n} ھۆججەت'],

  // ---------- 歌曲菜单 ----------
  'track.addToPlaylist': ['添加到歌单', '加入歌單', 'Add to playlist', 'プレイリストに追加', '플레이리스트에 추가', '', 'تىزىملىككە قوشۇش'],
  'track.like': ['喜欢', '喜歡', 'Like', 'お気に入り', '좋아요', 'དགའ་མོས།', 'ياقتۇرۇش'],
  'track.unlike': ['取消喜欢', '取消喜歡', 'Unlike', 'お気に入り解除', '좋아요 취소', '', 'ياقتۇرۇشنى بىكار قىلىش'],
  'track.removeFromPlaylist': ['从本歌单移出', '從本歌單移出', 'Remove from playlist', 'このプレイリストから削除', '이 플레이리스트에서 삭제', '', ''],
  'track.download': ['下载到本地', '下載到本地', 'Download', 'ダウンロード', '다운로드', 'ཕབ་ལེན།', 'چۈشۈرۈش'],
  'track.downloaded': ['已下载', '已下載', 'Downloaded', 'ダウンロード済み', '다운로드됨', '', 'چۈشۈرۈلدى'],
  'track.downloading': ['下载中 {p}%', '下載中 {p}%', 'Downloading {p}%', 'ダウンロード中 {p}%', '다운로드 중 {p}%', '', ''],
  'track.deleteTitle': ['删除歌曲', '刪除歌曲', 'Delete song', '曲を削除', '곡 삭제', '', 'ناخشىنى ئۆچۈرۈش'],
  'track.deleteBody1': ['将从曲库中移除这首歌。', '將從音樂庫中移除這首歌。', 'This song will be removed from your library.', 'この曲をライブラリから削除します。', '이 곡을 라이브러리에서 삭제합니다.', '', ''],
  'track.deleteBody2': [
    '收藏、最近播放、歌单引用与离线缓存会一起清掉。',
    '收藏、最近播放、歌單引用與離線快取會一起清掉。',
    'Likes, history, playlist entries and offline cache are cleared too.',
    'お気に入り・再生履歴・プレイリスト・オフラインキャッシュも削除されます。',
    '좋아요, 재생 기록, 플레이리스트, 오프라인 캐시도 함께 삭제됩니다.',
    '',
    ''
  ],
  'track.deleteBody3': [
    '本地文件和网盘文件都不会被删除，重新扫描目录可以再加回来。',
    '本地檔案和網盤檔案都不會被刪除，重新掃描目錄可以再加回來。',
    'The original file is not deleted — rescan the folder to add it back.',
    '元のファイルは削除されません。フォルダを再スキャンすれば戻せます。',
    '원본 파일은 삭제되지 않습니다. 폴더를 다시 스캔하면 복구됩니다.',
    '',
    ''
  ],
  'track.deleted': ['已删除《{t}》', '已刪除《{t}》', 'Deleted "{t}"', '「{t}」を削除しました', '"{t}" 삭제됨', '', ''],

  // ---------- 缓存上限 / 清除 ----------
  'cache.title': ['缓存大小上限', '快取大小上限', 'Cache size limit', 'キャッシュ容量の上限', '캐시 크기 한도', '', ''],
  'cache.sub': ['超出后自动清理最早的缓存', '超出後自動清理最早的快取', 'Oldest cache is removed automatically', '上限を超えると古い順に削除されます', '초과하면 오래된 캐시부터 정리됩니다', '', ''],
  'cache.unlimited': ['不限制', '不限制', 'Unlimited', '制限なし', '제한 없음', '', 'چەكسىز'],
  'confirm.clearAudio': ['清除', '清除', 'Clear', '削除', '지우기', '', 'تازىلاش'],
  'confirm.clearAll': ['确认清除', '確認清除', 'Clear all', '削除する', '모두 지우기', '', ''],
  'confirm.cancel': ['取消', '取消', 'Cancel', 'キャンセル', '취소', 'ཕྱིར་འཐེན།', 'بىكار قىلىش'],
  'confirm.typeHint': [
    '确认请在下框输入 {w}',
    '確認請在下框輸入 {w}',
    'Type {w} below to confirm',
    '確認のため下の欄に {w} と入力してください',
    '확인하려면 아래에 {w} 를 입력하세요',
    '',
    ''
  ],

  // ---------- 清除缓存 / 清除全部数据 ----------
  'clearAudio.subEmpty': ['当前没有缓存', '目前沒有快取', 'No cache right now', 'キャッシュはありません', '캐시가 없습니다', '', ''],
  'clearAudio.l1': [
    '将删除已缓存的音频文件（约 {mb} MB）。',
    '將刪除已快取音訊檔案（約 {mb} MB）。',
    'Cached audio files (~{mb} MB) will be deleted.',
    'キャッシュされた音声ファイル（約 {mb} MB）を削除します。',
    '캐시된 오디오 파일(약 {mb} MB)을 삭제합니다.',
    '',
    ''
  ],
  'clearAudio.l2': [
    '曲库、封面、歌词都不受影响，联网时可以重新缓存。',
    '音樂庫、封面、歌詞都不受影響，連網時可以重新快取。',
    'Library, covers and lyrics are untouched — it re-caches when online.',
    'ライブラリ・カバー・歌詞は影響を受けません。オンライン時に再キャッシュされます。',
    '라이브러리, 커버, 가사는 그대로입니다. 온라인일 때 다시 캐시됩니다.',
    '',
    ''
  ],
  'clearAudio.done': ['已清除边听缓存', '已清除邊聽快取', 'Play cache cleared', '再生キャッシュを削除しました', '재생 캐시를 지웠습니다', '', ''],
  'reset.title': ['清除所有数据', '清除所有資料', 'Clear all data', 'すべてのデータを削除', '모든 데이터 지우기', '', ''],
  'reset.sub': ['这一步不可撤销', '這一步無法復原', 'This cannot be undone', 'この操作は取り消せません', '되돌릴 수 없습니다', '', ''],
  'reset.l0': ['将清除：', '將清除：', 'This will remove:', '削除されるもの：', '삭제되는 항목:', '', ''],
  'reset.l1': ['· 全部歌曲（{n} 首）', '· 全部歌曲（{n} 首）', '· All songs ({n})', '· すべての曲（{n} 曲）', '· 모든 곡({n}곡)', '', ''],
  'reset.l2': ['· 收藏与最近播放', '· 收藏與最近播放', '· Likes and history', '· お気に入りと再生履歴', '· 좋아요와 재생 기록', '', ''],
  'reset.l3': [
    '· 离线缓存、已下载的封面与歌词',
    '· 離線快取、已下載的封面與歌詞',
    '· Offline cache, downloaded covers and lyrics',
    '· オフラインキャッシュ、取得済みのカバーと歌詞',
    '· 오프라인 캐시, 내려받은 커버와 가사',
    '',
    ''
  ],
  'reset.l4': ['· 搜索历史', '· 搜尋紀錄', '· Search history', '· 検索履歴', '· 검색 기록', '', ''],
  'reset.l5': [
    '会保留：已添加的目录与音乐来源，之后在「音乐来源」里重新扫描即可把歌加回来。',
    '會保留：已加入的目錄與音樂來源，之後在「音樂來源」裡重新掃描即可把歌加回來。',
    'Kept: added folders and sources — rescan them to bring the songs back.',
    '保持されるもの：追加済みのフォルダと取得元。再スキャンすれば曲は戻ります。',
    '유지되는 항목: 추가한 폴더와 소스. 다시 스캔하면 곡이 복구됩니다.',
    '',
    ''
  ],

  // ---------- 语言选择 ----------
  'lang.title': ['语言', '語言', 'Language', '言語', '언어', 'སྐད་ཡིག', 'تىل'],
  'lang.sub': ['界面语言', '介面語言', 'Interface language', '表示言語', '인터페이스 언어', '', 'كۆرۈنمە تىلى'],
  'lang.system': ['跟随系统', '跟隨系統', 'Follow system', 'システムに従う', '시스템 설정', 'རྒྱུད་ཁོངས་ལ་བརྟེན།', 'سىستېمىغا ئەگىشىش'],
  'lang.systemSub': [
    '自动匹配手机语言',
    '自動匹配手機語言',
    'Match your device language',
    '端末の言語に合わせる',
    '기기 언어에 맞춤',
    '',
    ''
  ],
  'lang.current': ['当前', '目前', 'Current', '現在', '현재', '', 'ھازىرقى'],

  // ---------- 保存目录 ----------
  'import.scanning': ['正在扫描本机音乐…', '正在掃描本機音樂…', 'Scanning this device…', '端末内をスキャン中…', '기기 스캔 중…', '', ''],
  'import.failed': ['导入中断：{e}', '匯入中斷：{e}', 'Import stopped: {e}', '取り込み中断：{e}', '가져오기 중단: {e}', '', ''],
  'import.progress': ['正在扫描入库 {a}/{b}', '正在掃描入庫 {a}/{b}', 'Scanning {a}/{b}', 'スキャン中 {a}/{b}', '스캔 중 {a}/{b}', '', ''],
  'import.done': ['导入完成：新增 {n} 首', '匯入完成：新增 {n} 首', 'Import done: {n} new songs', '取り込み完了：{n} 曲追加', '가져오기 완료: {n}곡 추가', '', ''],
  'import.skipped': ['，已有 {n} 首跳过', '，已有 {n} 首跳過', ', {n} already existed', '、既存 {n} 曲', ', 기존 {n}곡', '', ''],
  'badgeNoTag': ['无标签', '無標籤', 'No tags', 'タグなし', '태그 없음', '', ''],
  'dir.title': ['音乐保存目录', '音樂儲存目錄', 'Music folder', '音楽の保存先', '음악 저장 위치', 'རོལ་དབྱངས་ཉར་ས།', 'مۇزىكا ساقلاش مۇندەرىجىسى'],
  'dir.sub': ['下载到本地时保存到这里', '下載到本地時儲存到這裡', 'Where downloaded songs are saved', 'ダウンロードした曲の保存先', '다운로드한 곡의 저장 위치', '', ''],
  'dir.publicMusic': ['公共音乐目录', '公共音樂目錄', 'Public Music folder', '公開の Music フォルダ', '공용 Music 폴더', '', 'ئورتاق مۇزىكا مۇندەرىجىسى'],
  'dir.publicMusicSub': [
    '其他播放器也能看到这些文件',
    '其他播放器也能看到這些檔案',
    'Other music apps can see these files',
    '他の音楽アプリからも見えます',
    '다른 음악 앱에서도 볼 수 있습니다',
    '',
    ''
  ],
  'dir.publicDownload': ['系统下载目录', '系統下載目錄', 'System Download folder', 'システムの Download フォルダ', '시스템 Download 폴더', '', 'سىستېما چۈشۈرۈش مۇندەرىجىسى'],
  'dir.publicDownloadSub': ['和浏览器下载的文件放在一起', '和瀏覽器下載的檔案放在一起', 'Same place as browser downloads', 'ブラウザのダウンロードと同じ場所', '브라우저 다운로드와 같은 위치', '', ''],
  'dir.app': ['应用专属目录', '應用專屬目錄', 'App private folder', 'アプリ専用フォルダ', '앱 전용 폴더', '', 'ئەپكە خاس مۇندەرىجە'],
  'dir.appSub': [
    '无需授权，卸载应用时一起删除',
    '無需授權，卸載應用時一起刪除',
    'No permission needed, removed with the app',
    '権限不要。アプリ削除時に一緒に消えます',
    '권한 불필요, 앱 삭제 시 함께 삭제됨',
    '',
    ''
  ],
  'dir.needPermission': [
    '写入公共目录需要「所有文件访问」权限，请在系统设置里允许',
    '寫入公共目錄需要「所有檔案存取」權限，請在系統設定裡允許',
    'Writing to a public folder needs "All files access" — please allow it in system settings',
    '公開フォルダへの書き込みには「すべてのファイルへのアクセス」権限が必要です',
    '공용 폴더에 쓰려면 "모든 파일 접근" 권한이 필요합니다',
    '',
    ''
  ],
  'dir.fallback': [
    '没有拿到权限，这次先存到应用专属目录',
    '沒有取得權限，這次先存到應用專屬目錄',
    'Permission not granted — saved to the app folder instead',
    '権限がないため、アプリ専用フォルダに保存しました',
    '권한이 없어 앱 전용 폴더에 저장했습니다',
    '',
    ''
  ],
  'dir.saved': ['已保存到 {p}', '已儲存到 {p}', 'Saved to {p}', '{p} に保存しました', '{p}에 저장했습니다', '', ''],
  'dir.failed': ['下载失败：{e}', '下載失敗：{e}', 'Download failed: {e}', 'ダウンロード失敗：{e}', '다운로드 실패: {e}', '', ''],

  // ---------- 音乐来源 ----------
  'src.title': ['音乐来源', '音樂來源', 'Music sources', '音楽の取得元', '음악 소스', '', 'مۇزىكا مەنبەسى'],
  'src.add': ['添加音乐来源', '加入音樂來源', 'Add music source', '取得元を追加', '음악 소스 추가', '', 'مۇزىكا مەنبەسى قوشۇش'],
  'src.addSub': [
    '先选一个来源，再挑要导入的目录',
    '先選一個來源，再挑要匯入的目錄',
    'Pick a source, then choose the folder to import',
    '取得元を選んでから、取り込むフォルダを選びます',
    '소스를 선택한 뒤 가져올 폴더를 고르세요',
    '',
    ''
  ],
  'src.local': ['本地音乐', '本地音樂', 'On this device', 'この端末の音楽', '기기 내 음악', '', 'يەرلىك مۇزىكا'],
  'src.localSub': ['添加手机里的音乐目录', '加入手機裡的音樂目錄', 'Add a music folder from this phone', 'スマホ内の音楽フォルダを追加', '휴대폰의 음악 폴더 추가', '', ''],
  'src.webdav': ['WebDAV 网盘', 'WebDAV 網盤', 'WebDAV storage', 'WebDAV ストレージ', 'WebDAV 저장소', '', 'WebDAV تور دىسكىسى'],
  'src.webdavSub': [
    '群晖 / 坚果云 / Nextcloud / Alist · 用你自己的账号',
    '群暉 / 堅果雲 / Nextcloud / Alist · 用你自己的帳號',
    'Synology / Nutstore / Nextcloud / Alist — your own account',
    'Synology / Nutstore / Nextcloud / Alist — ご自身のアカウント',
    'Synology / Nutstore / Nextcloud / Alist — 본인 계정',
    '',
    ''
  ],
  'src.webdavAdd': ['再连一个 WebDAV 账号', '再連一個 WebDAV 帳號', 'Connect another WebDAV account', 'WebDAV アカウントを追加', 'WebDAV 계정 추가', '', ''],
  'src.folders': ['已添加的目录', '已加入的目錄', 'Added folders', '追加済みのフォルダ', '추가한 폴더', '', 'قوشۇلغان مۇندەرىجە'],
  'src.none': ['还没有添加任何来源', '還沒有加入任何來源', 'No source added yet', '取得元がまだありません', '아직 추가한 소스가 없습니다', '', ''],
  'src.prose': [
    '添加音乐只有两条路：扫描手机本地，或者把网盘目录导入成索引。源文件都不搬家。',
    '加入音樂只有兩條路：掃描手機本地，或者把網盤目錄匯入成索引。原始檔案都不搬家。',
    'Two ways to add music: scan this phone, or index a cloud folder. Your files never move.',
    '音楽の追加方法は 2 つ：スマホ内をスキャンするか、クラウドのフォルダを索引化するか。ファイルは移動しません。',
    '음악을 추가하는 방법은 두 가지입니다: 휴대폰을 스캔하거나 클라우드 폴더를 색인하는 것. 파일은 이동하지 않습니다.',
    '',
    ''
  ],
  'src.localScanning': [
    '正在读取媒体库并解析标签 {p}%',
    '正在讀取媒體庫並解析標籤 {p}%',
    'Reading media library and tags {p}%',
    'メディアライブラリとタグを読み込み中 {p}%',
    '미디어 라이브러리와 태그 읽는 중 {p}%',
    '',
    ''
  ],
  'src.scanAll': [
    '或者直接扫描手机里全部音乐',
    '或者直接掃描手機裡全部音樂',
    'Or scan all music on this phone',
    'スマホ内の音楽をすべてスキャン',
    '휴대폰의 모든 음악 스캔',
    '',
    ''
  ],
  'src.upcoming': ['后续版本支持', '後續版本支援', 'Coming later', '今後の対応', '추후 지원', '', ''],
  'src.soon': ['即将支持', '即將支援', 'Soon', '近日対応', '곧 지원', '', ''],
  'src.privacyTitle': ['数据只留在本机', '資料只留在本機', 'Your data stays on this device', 'データは端末内のみ', '데이터는 기기에만', '', ''],
  'src.privacyBody': [
    '本地音乐只读取媒体库索引与文件标签；WebDAV 密码存在系统钥匙串，播放走你服务器的直链，不经过任何中转。',
    '本地音樂只讀取媒體庫索引與檔案標籤；WebDAV 密碼存在系統鑰匙圈，播放走你伺服器的直鏈，不經過任何中轉。',
    'Local music only reads the media index and file tags. WebDAV passwords live in the system keychain, and playback goes straight to your server.',
    'ローカル音楽はメディア索引とタグのみを読み取ります。WebDAV のパスワードはシステムキーチェーンに保存され、再生はサーバーへ直接接続します。',
    '로컬 음악은 미디어 색인과 태그만 읽습니다. WebDAV 비밀번호는 시스템 키체인에 저장되고 재생은 서버로 직접 연결됩니다.',
    '',
    ''
  ],
};

/// 取文案：L.of(context).xxx
class L {
  const L(this.lang);

  final AppLang lang;

  /// 跟随系统时的实际语言由 AppState 决定，这里只拿结果
  static AppLang current(BuildContext c) => c.read<AppState>().lang;

  static L of(BuildContext c) => L(c.watch<AppState>().lang);

  /// 不建立依赖（在回调里用）
  static L read(BuildContext c) => L(c.read<AppState>().lang);

  /// 取一条文案，[args] 替换 {key} 占位符
  String t(String key, [Map<String, String>? args]) {
    final row = _dict[key];
    if (row == null) return key;
    var v = row[lang.index];
    if (v.isEmpty) v = row[AppLang.en.index];
    if (v.isEmpty) v = row[0];
    if (args != null) {
      args.forEach((k, val) => v = v.replaceAll('{$k}', val));
    }
    return v;
  }

  /// 带数量的文案：L.of(context).songs(12)
  String songs(int n) => t('unit.songs', {'n': '$n'});
  String albums(int n) => t('unit.albums', {'n': '$n'});
  String artists(int n) => t('unit.artists', {'n': '$n'});
  String folders(int n) => t('unit.folders', {'n': '$n'});
  String playlists(int n) => t('unit.playlists', {'n': '$n'});

  // ---- 导航 ----
  String get tabHome => t('tab.home');
  String get tabBrowse => t('tab.browse');
  String get tabSearch => t('tab.search');
  String get tabMe => t('tab.me');

  // ---- 通用 ----
  String get ok => t('ok');
  String get cancel => t('cancel');
  String get delete => t('delete');
  String get save => t('save');
  String get close => t('close');
  String get done => t('done');
  String get retry => t('retry');
  String get all => t('all');
  String get next => t('next');
  String get gotIt => t('gotIt');
}
