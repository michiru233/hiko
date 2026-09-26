import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/online_models.dart';

/// 在线数据层纯逻辑单测（不联网）：字段解析、URL 构造、曲目树拍平与字幕配对。
/// 接口实测结论见 .workbuddy/memory/2026-09-25.md。
void main() {
  group('OnlineWork 解析', () {
    test('列表项字段解析', () {
      final work = OnlineWork.fromJson({
        'id': 1657200,
        'title': '巨乳ギャルJKとだらだら',
        'circle_id': 51931,
        'name': '青春×フェティシズム',
        'release': '2026-06-27',
        'create_date': '2026-08-07',
        'dl_count': 307937,
        'rate_count': 124,
        'rate_average_2dp': 4.9,
        'has_subtitle': true,
        'duration': 579,
        'nsfw': true,
        'source_id': 'RJ01657200',
      });

      expect(work.id, 1657200);
      expect(work.title, '巨乳ギャルJKとだらだら');
      expect(work.circleName, '青春×フェティシズム');
      expect(work.circleId, 51931);
      expect(work.release, DateTime.parse('2026-06-27'));
      expect(work.dlCount, 307937);
      expect(work.rateAverage, 4.9);
      expect(work.hasSubtitle, isTrue);
      expect(work.durationSeconds, 579);
      expect(work.rjCode, 'RJ01657200');
    });

    test('标题缺失时回退占位名而非空串', () {
      final work = OnlineWork.fromJson({'id': 1, 'title': '   '});
      expect(work.title, '未命名作品');
    });

    test('标签优先取中文 i18n，缺失时回退服务端 name', () {
      final work = OnlineWork.fromJson({
        'id': 1,
        'tags': [
          {
            'id': 222,
            'name': '幼なじみ',
            'i18n': {
              'ja-jp': {'name': '幼なじみ'},
              'zh-cn': {'name': '青梅竹马'},
            },
          },
          {
            'id': 496,
            'name': 'バイノーラル',
            'i18n': {
              'ja-jp': {'name': 'バイノーラル'},
            },
          },
        ],
      });
      // 1.94.0 起标签保留完整对象（带 id）—— 按标签筛选要的正是 id
      expect(work.tags.map((t) => t.name), ['青梅竹马', 'バイノーラル']);
      expect(work.tags.map((t) => t.id), [222, 496]);
    });

    test('标签兼容纯字符串数组且去重', () {
      final work = OnlineWork.fromJson({
        'id': 1,
        'tags': ['ASMR', 'ASMR', '  ', '治愈'],
      });
      expect(work.tags.map((t) => t.name), ['ASMR', '治愈']);
      // 纯字符串形态拿不到 id，用 0 表示「只展示、不可筛」
      expect(work.tags.every((t) => t.id == 0), isTrue);
    });

    test('标签按 id 去重（同名不同 id 视为两个标签）', () {
      final work = OnlineWork.fromJson({
        'id': 1,
        'tags': [
          {'id': 4, 'name': '亲热/甜蜜'},
          {'id': 4, 'name': '亲热/甜蜜'},
          {'id': 97, 'name': '亲热/甜蜜'},
        ],
      });
      expect(work.tags.length, 2);
      expect(work.tags.map((t) => t.id), [4, 97]);
    });

    test('声优解析兼容对象数组与字符串数组', () {
      final objects = OnlineWork.fromJson({
        'id': 1,
        'vas': [
          {'id': 'uuid-1', 'name': '加藤英美里'},
          {'id': 'uuid-2', 'name': '五十嵐裕美'},
        ],
      });
      expect(objects.vas, ['加藤英美里', '五十嵐裕美']);

      final strings = OnlineWork.fromJson({
        'id': 1,
        'vas': ['春花らん'],
      });
      expect(strings.vas, ['春花らん']);
    });

    test('source_id 归一为大写 RJ 号，非 RJ 作品返回 null', () {
      expect(OnlineWork.fromJson({'id': 1, 'source_id': 'rj01657200'}).rjCode,
          'RJ01657200');
      expect(OnlineWork.fromJson({'id': 1, 'source_id': 'RE123456'}).rjCode,
          isNull);
      expect(OnlineWork.fromJson({'id': 1, 'source_id': ''}).rjCode, isNull);
      expect(OnlineWork.fromJson({'id': 1}).rjCode, isNull);
    });

    test('在线专辑 id 与 sourcePath 采用约定前缀，供播放层判断来源', () {
      final work = OnlineWork.fromJson({'id': 99, 'title': 'x'});
      expect(work.albumId, 'online-99');
      expect(OnlineWork.sourcePathFor(99), 'online://99');
    });

    test('durationLabel 按小时/分钟格式化，0 秒返回空串', () {
      expect(OnlineWork.fromJson({'id': 1, 'duration': 0}).durationLabel, '');
      expect(OnlineWork.fromJson({'id': 1, 'duration': 59}).durationLabel, '0:59');
      expect(
          OnlineWork.fromJson({'id': 1, 'duration': 754}).durationLabel, '12:34');
      expect(OnlineWork.fromJson({'id': 1, 'duration': 5025}).durationLabel,
          '1:23:45');
    });

    test('merged 用详情补齐列表缺失的 tags/vas', () {
      final listItem = OnlineWork.fromJson({
        'id': 7,
        'title': '列表标题',
        'duration': 100,
      });
      final detail = OnlineWork.fromJson({
        'id': 7,
        'title': '列表标题',
        'duration': 100,
        'tags': ['治愈'],
        'vas': ['春花らん'],
        'dl_count': 42,
      });
      final merged = listItem.merged(detail);
      expect(merged.tags.map((t) => t.name), ['治愈']);
      expect(merged.vas, ['春花らん']);
      expect(merged.dlCount, 42);
    });

    test('列表项自己就带 tags/vas —— 1.90 的「列表不返回」是误判', () {
      // 这条用一个「列表形态」的响应（带 tags/vas、无 progress）验证：
      // 1.94.0 之前 OnlineWork.tags 只留名字，就是基于那个误判做的设计
      final work = OnlineWork.fromJson({
        'id': 243448,
        'title': '列表标题',
        'tags': [
          {
            'id': 222,
            'name': '青梅竹马',
            'i18n': {
              'ja-jp': {'name': '幼なじみ'},
              'zh-cn': {'name': '青梅竹马'},
            },
          },
        ],
        'vas': [
          {'id': 'uuid', 'name': '加藤英美里'},
        ],
      });
      expect(work.tags.single.id, 222);
      expect(work.tags.single.name, '青梅竹马');
      expect(work.vas, ['加藤英美里']);
    });
  });

  group('OnlineWorkPage 分页', () {
    test('解析 pagination 与 hasMore', () {
      final page = OnlineWorkPage.fromJson({
        'works': [
          {'id': 1, 'title': 'a'},
          {'id': 2, 'title': 'b'},
        ],
        'pagination': {'currentPage': 2, 'pageSize': 2, 'totalCount': 10},
      });
      expect(page.works.length, 2);
      expect(page.currentPage, 2);
      expect(page.totalCount, 10);
      expect(page.hasMore, isTrue);

      final last = OnlineWorkPage.fromJson({
        'works': [
          {'id': 9, 'title': 'z'},
        ],
        'pagination': {'currentPage': 5, 'pageSize': 2, 'totalCount': 10},
      });
      expect(last.hasMore, isFalse);
    });
  });

  group('KikoeruClient 地址与 URL 构造', () {
    test('normalizeBase 补 https 并去尾斜杠', () {
      expect(KikoeruClient.normalizeBase('api.asmr.one'), 'https://api.asmr.one');
      expect(KikoeruClient.normalizeBase('https://api.asmr.one/'),
          'https://api.asmr.one');
      expect(KikoeruClient.normalizeBase('  https://api.asmr-200.com//  '),
          'https://api.asmr-200.com');
    });

    test('normalizeBase 对本机与内网地址用 http', () {
      expect(KikoeruClient.normalizeBase('localhost:8888'),
          'http://localhost:8888');
      expect(KikoeruClient.normalizeBase('192.168.1.10:8888'),
          'http://192.168.1.10:8888');
      expect(KikoeruClient.normalizeBase('127.0.0.1:8888'),
          'http://127.0.0.1:8888');
    });

    test('normalizeBase 空值回退官方默认实例', () {
      expect(KikoeruClient.normalizeBase(''),
          KikoeruClient.officialMirrors.first);
      expect(KikoeruClient.normalizeBase('   '),
          KikoeruClient.officialMirrors.first);
    });

    test('官方实例与自建服务器的镜像回退范围不同', () {
      // 自建服务器不得跨站重试到 asmr.one
      final custom = KikoeruClient(baseUrl: 'http://192.168.1.5:8888');
      expect(custom.isOfficial, isFalse);
      expect(custom.baseUrl, 'http://192.168.1.5:8888');

      final official = KikoeruClient(baseUrl: 'api.asmr-100.com');
      expect(official.isOfficial, isTrue);
      expect(official.baseUrl, 'https://api.asmr-100.com');
    });

    test('hashFromStreamUrl 反解服务端 hash', () {
      expect(
        KikoeruClient.hashFromStreamUrl(
            'https://api.asmr.one/api/media/stream/1657200/1937305'),
        '1657200/1937305',
      );
      expect(KikoeruClient.hashFromStreamUrl('file:///tmp/a.mp3'), isNull);
      expect(
          KikoeruClient.hashFromStreamUrl('https://x/api/media/stream/'), isNull);
    });

    test('coverUrl 支持原图与缩略图两种形态', () {
      final client = KikoeruClient(baseUrl: 'https://api.asmr.one');
      expect(client.coverUrl(123),
          'https://api.asmr.one/api/cover/123.jpg');
      // 1.93.0：列表也走原图。显式 type=main 与不带参数是同一张图（实测 md5 相同）
      expect(client.coverUrl(123, size: KikoeruClient.coverMainSize),
          'https://api.asmr.one/api/cover/123.jpg?type=main');
      expect(client.coverUrl(123, size: KikoeruClient.coverThumbSize),
          'https://api.asmr.one/api/cover/123.jpg?type=240x240');
    });

    test('streamUrl 走服务端签发入口而非裸 CDN 直链', () {
      final client = KikoeruClient(baseUrl: 'https://api.asmr.one');
      expect(client.streamUrl('1657200/1937305'),
          'https://api.asmr.one/api/media/stream/1657200/1937305');
    });
  });

  group('曲目树解析（拍平 + 字幕配对）', () {
    test('拍平嵌套 folder 并保留相对路径', () {
      final tracks = KikoeruClient.parseTrackTree([
        {
          'type': 'folder',
          'title': '02英語',
          'children': [
            {
              'type': 'folder',
              'title': '01：mp3',
              'children': [
                {
                  'type': 'audio',
                  'title': 'track01.mp3',
                  'hash': '1/11',
                  'size': 1234,
                },
              ],
            },
          ],
        },
        {
          'type': 'audio',
          'title': 'root.mp3',
          'hash': '1/12',
          'size': 99,
        },
      ]);

      final nested = tracks.firstWhere((t) => t.title == 'track01.mp3');
      expect(nested.relativePath, '02英語/01：mp3');
      expect(nested.hash, '1/11');
      expect(nested.size, 1234);
      expect(nested.isAudio, isTrue);

      final root = tracks.firstWhere((t) => t.title == 'root.mp3');
      expect(root.relativePath, '');
    });

    test('duration 字段（浮点秒）被解析，缺失/字幕文件为 0', () {
      // 1.91.0：原先只取了 size，导致在线详情页曲目行没有时长可显示。
      // 服务端给的是浮点（实测 291.4832），不是整数。
      final tracks = KikoeruClient.parseTrackTree([
        {'type': 'audio', 'title': 'a.mp3', 'hash': '1/1', 'duration': 291.4832},
        {'type': 'audio', 'title': 'b.mp3', 'hash': '1/2'},
        {'type': 'text', 'title': 'b.lrc', 'hash': '1/3', 'duration': 12},
      ]);

      expect(tracks.firstWhere((t) => t.hash == '1/1').duration,
          closeTo(291.4832, 0.0001));
      expect(tracks.firstWhere((t) => t.hash == '1/2').duration, 0);
    });

    test('同目录同名 .lrc 配对到音轨', () {
      final tracks = KikoeruClient.parseTrackTree([
        {
          'type': 'folder',
          'title': '01：mp3',
          'children': [
            {'type': 'audio', 'title': 'track01.mp3', 'hash': '1/11'},
            {'type': 'text', 'title': 'track01.lrc', 'hash': '1/21'},
          ],
        },
      ]);

      final audio = tracks.firstWhere((t) => t.isAudio);
      expect(audio.lyricsHash, '1/21');
      expect(audio.lyricsTitle, 'track01.lrc');
    });

    test('双扩展名（track01.mp3.vtt）也能配对', () {
      final tracks = KikoeruClient.parseTrackTree([
        {
          'type': 'folder',
          'title': 'sub',
          'children': [
            {'type': 'audio', 'title': 'track01.mp3', 'hash': '1/11'},
            {'type': 'text', 'title': 'track01.mp3.vtt', 'hash': '1/31'},
          ],
        },
      ]);

      expect(tracks.firstWhere((t) => t.isAudio).lyricsHash, '1/31');
    });

    test('不同目录的字幕不越目录配对', () {
      final tracks = KikoeruClient.parseTrackTree([
        {
          'type': 'folder',
          'title': 'A',
          'children': [
            {'type': 'audio', 'title': 'track01.mp3', 'hash': '1/11'},
          ],
        },
        {
          'type': 'folder',
          'title': 'B',
          'children': [
            {'type': 'text', 'title': 'track01.lrc', 'hash': '1/21'},
          ],
        },
      ]);

      expect(tracks.firstWhere((t) => t.isAudio).lyricsHash, isNull);
    });

    test('无 hash 的节点被跳过，非音频文件不参与播放', () {
      final tracks = KikoeruClient.parseTrackTree([
        {'type': 'audio', 'title': 'bad.mp3'},
        {'type': 'image', 'title': 'cover.jpg', 'hash': '1/41'},
        {'type': 'audio', 'title': 'ok.mp3', 'hash': '1/51'},
      ]);

      expect(tracks.length, 2);
      expect(tracks.where((t) => t.playable).length, 1);
      expect(tracks.firstWhere((t) => t.playable).hash, '1/51');
    });
  });

  group('展示格式化', () {
    test('formatOnlineCount 中文习惯缩写', () {
      expect(formatOnlineCount(0), '0');
      expect(formatOnlineCount(9999), '9999');
      expect(formatOnlineCount(307937), '30.8万');
      expect(formatOnlineCount(120000000), '1.2亿');
    });

    test('formatOnlineDate', () {
      expect(formatOnlineDate(null), '');
      expect(formatOnlineDate(DateTime(2026, 6, 27)), '2026-06-27');
      expect(formatOnlineDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('onlineTrackDisplayName 剥扩展名，但不误伤含点的长标题', () {
      expect(onlineTrackDisplayName('track01.mp3'), 'track01');
      expect(onlineTrackDisplayName('track01.wav'), 'track01');
      expect(onlineTrackDisplayName('  '), '未命名音轨');
      expect(onlineTrackDisplayName('no-ext'), 'no-ext');
      // 点后面超过 6 个字符视为标题的一部分，不当扩展名剁掉
      expect(onlineTrackDisplayName('第1話.ボイスドラマ'),
          '第1話.ボイスドラマ');
    });

    test('onlineWorkPageUrl 把 API 域名映射到网页域名', () {
      // 实测 https://api.asmr.one/works/{id} 返回 404，网页在 www.asmr.one
      expect(onlineWorkPageUrl('https://api.asmr.one', 1657200),
          'https://www.asmr.one/works/1657200');
      expect(onlineWorkPageUrl('https://api.asmr-200.com/', 5),
          'https://www.asmr.one/works/5');
      // 自建 Kikoeru 的 API 与网页同 host
      expect(onlineWorkPageUrl('http://192.168.1.5:8888', 7),
          'http://192.168.1.5:8888/works/7');
      expect(onlineWorkPageUrl('', 7), 'https://www.asmr.one/works/7');
    });
  });

  group('节点树还原（不限深度 + 目录聚合）', () {
    List<Map<String, dynamic>> deepNodes() => [
          {
            'type': 'audio',
            'title': 'root.mp3',
            'hash': '1/1',
            'duration': 10,
          },
          {
            'type': 'folder',
            'title': 'L1',
            'children': [
              {
                'type': 'folder',
                'title': 'L2',
                'children': [
                  {
                    'type': 'folder',
                    'title': 'L3',
                    'children': [
                      {
                        'type': 'audio',
                        'title': 'deep.mp3',
                        'hash': '1/2',
                        'duration': 291.4832,
                      },
                      {'type': 'text', 'title': 'deep.lrc', 'hash': '1/9'},
                    ],
                  },
                ],
              },
            ],
          },
          {
            'type': 'folder',
            'title': '只有字幕',
            'children': [
              {'type': 'text', 'title': 'only.lrc', 'hash': '1/10'},
            ],
          },
        ];

    test('还原 3 层以上目录，不限深度', () {
      final nodes = deepNodes();
      final flat = KikoeruClient.parseTrackTree(nodes);
      final tree = KikoeruClient.parseTrackNodes(nodes, flat);

      // 顶层顺序保持服务端顺序：先文件后目录
      expect(tree.first, isA<OnlineFileNode>());

      final l1 = tree.whereType<OnlineFolderNode>().first;
      expect(l1.title, 'L1');
      final l2 = l1.children.whereType<OnlineFolderNode>().first;
      expect(l2.title, 'L2');
      final l3 = l2.children.whereType<OnlineFolderNode>().first;
      expect(l3.title, 'L3');

      final deep = l3.children.whereType<OnlineFileNode>().first.track;
      expect(deep.hash, '1/2');
      // 按 hash 取回同一条记录：字幕配对结果不会出现第二份不同步的副本
      expect(identical(deep, flat.firstWhere((t) => t.hash == '1/2')), isTrue);
      expect(deep.lyricsHash, '1/9');
    });

    test('目录递归聚合项目数与总时长，纯字幕目录计 0', () {
      final nodes = deepNodes();
      final tree = KikoeruClient.parseTrackNodes(
          nodes, KikoeruClient.parseTrackTree(nodes));
      final folders = tree.whereType<OnlineFolderNode>().toList();

      final l1 = folders.firstWhere((f) => f.title == 'L1');
      expect(l1.audioCount, 1);
      expect(l1.totalSeconds, closeTo(291.4832, 0.0001));

      final empty = folders.firstWhere((f) => f.title == '只有字幕');
      expect(empty.audioCount, 0);
      expect(empty.totalSeconds, 0);
    });

    test('playableIn 递归收集目录下全部可播放音频', () {
      final nodes = deepNodes();
      final tree = KikoeruClient.parseTrackNodes(
          nodes, KikoeruClient.parseTrackTree(nodes));
      final l1 = tree.whereType<OnlineFolderNode>().first;

      // L1 里只有 1 条音频（deep.mp3），字幕不进队列
      expect(playableIn(l1).map((t) => t.hash), ['1/2']);
    });

    test('folderKeysIn 只收含音频的目录，否则「全部折叠」永远达不到', () {
      final nodes = deepNodes();
      final tree = KikoeruClient.parseTrackNodes(
          nodes, KikoeruClient.parseTrackTree(nodes));

      expect(folderKeysIn(tree), ['L1', 'L1/L2', 'L1/L2/L3']);
    });

    test('目录无音频时其子目录也不收进折叠键', () {
      final nodes = [
        {
          'type': 'folder',
          'title': 'A',
          'children': [
            {
              'type': 'folder',
              'title': 'B',
              'children': [
                {'type': 'text', 'title': 'x.lrc', 'hash': '1/1'},
              ],
            },
          ],
        },
      ];
      final tree = KikoeruClient.parseTrackNodes(
          nodes, KikoeruClient.parseTrackTree(nodes));
      expect(folderKeysIn(tree), isEmpty);
    });
  });

  group('pathToHash（自动展开正在播放的那一行）', () {
    // L1 下既有直属音频（a.mp3）又有更深的目录链，用来区分
    // 「命中直属子文件」与「命中深层文件」两种返回形态
    List<OnlineNode> buildTree() {
      final nodes = [
        {'type': 'audio', 'title': 'root.mp3', 'hash': '1/1', 'duration': 10},
        {
          'type': 'folder',
          'title': 'L1',
          'children': [
            {'type': 'audio', 'title': 'a.mp3', 'hash': '1/2', 'duration': 5},
            {
              'type': 'folder',
              'title': 'L2',
              'children': [
                {
                  'type': 'folder',
                  'title': 'L3',
                  'children': [
                    {
                      'type': 'audio',
                      'title': 'deep.mp3',
                      'hash': '1/3',
                      'duration': 5,
                    },
                  ],
                },
              ],
            },
          ],
        },
      ];
      return KikoeruClient.parseTrackNodes(
        nodes,
        KikoeruClient.parseTrackTree(nodes),
      );
    }

    test('深层文件返回由浅到深的完整目录链', () {
      // 第一版实现「先递归再检查 children」，深层命中时把上层路径丢了，
      // 只返回 L1/L2/L3，于是展开集合里缺了父级、目标行照样看不见。
      expect(pathToHash(buildTree(), '1/3'), ['L1', 'L1/L2', 'L1/L2/L3']);
    });

    test('文件直属该目录时只返回这一层', () {
      expect(pathToHash(buildTree(), '1/2'), ['L1']);
    });

    test('根级文件与不在树里的 hash 都返回空', () {
      // 根级文件本来就可见，没有目录要展开 —— 空列表不是错误
      expect(pathToHash(buildTree(), '1/1'), isEmpty);
      expect(pathToHash(buildTree(), '1657200/1937305'), isEmpty);
      expect(pathToHash(const [], '1/3'), isEmpty);
    });

    test('返回的路径键与 folderKeysIn 同一套拼法', () {
      // 两者拼法一旦漂移，「展开全部」的判定和自动展开就会各说各话
      final tree = buildTree();
      final keys = folderKeysIn(tree).toSet();
      expect(pathToHash(tree, '1/3'), isNotEmpty);
      for (final path in pathToHash(tree, '1/3')) {
        expect(keys, contains(path));
      }
    });
  });

  group('OnlineSort（asmr.one 形态的扁平排序菜单）', () {
    test('5 项、顺序固定、方向写进条目名', () {
      // 方向写进名字是 1.92.0 的关键取舍：菜单里没有「再点一次反转」
      // 这种隐藏状态，所以条目名必须自带升降序语义。
      expect(OnlineSort.values.map((s) => s.label).toList(), [
        '最新收录',
        '发售日期倒序',
        '销量倒序',
        '评价倒序',
        'RJ 号倒序',
      ]);
    });

    test('order 键全在服务端白名单内且不重复', () {
      // 白名单外的值实测一律 400（source_id / work_id / release_date …）；
      // rating 在白名单里但匿名请求返回 0 条（要登录），所以刻意不收。
      const whitelist = {
        'create_date',
        'release',
        'dl_count',
        'price',
        'rate_average_2dp',
        'review_count',
        'id',
      };
      final keys = OnlineSort.values.map((s) => s.key).toList();
      expect(keys.toSet().length, keys.length);
      for (final key in keys) {
        expect(whitelist, contains(key));
      }
      expect(keys, isNot(contains('rating')));
    });

    test('甲方案 5 项全为倒序，方向是常量不是参数', () {
      expect(OnlineSort.sortParam, 'desc');
    });

    test('预设指向：热门 = 销量倒序，最新 = 发售日期倒序', () {
      expect(OnlineSort.popularPreset, OnlineSort.dlCountDesc);
      expect(OnlineSort.latestPreset, OnlineSort.releaseDesc);
    });
  });

  group('播放 URL 反查 hash', () {
    test('流播 URL 与缓存文件两种形态都能反解', () {
      // 流播
      expect(
        KikoeruClient.hashFromPlaybackUrl(
            'https://api.asmr.one/api/media/stream/1657200/1937305'),
        '1657200/1937305',
      );
      // 命中磁盘缓存：hash 里的 / 被 _sanitize 换成 _
      expect(
        KikoeruClient.hashFromPlaybackUrl(
            'file:///Users/x/Library/Caches/hiko/online/1657200_1937305.mp3'),
        '1657200/1937305',
      );
      // 无扩展名的缓存文件同样可解
      expect(
        KikoeruClient.hashFromPlaybackUrl('file:///tmp/1657200_1937305'),
        '1657200/1937305',
      );
    });

    test('无法识别的 URL 返回 null', () {
      expect(KikoeruClient.hashFromPlaybackUrl('file:///tmp/nohash.mp3'), isNull);
      expect(KikoeruClient.hashFromPlaybackUrl('file:///tmp/_.mp3'), isNull);
      expect(KikoeruClient.hashFromPlaybackUrl('https://x/other/a'), isNull);
      expect(
          KikoeruClient.hashFromPlaybackUrl('https://x/api/media/stream/'),
          isNull);
    });
  });

  group('分页条页码序列（首页/末页 + 当前页 ±2）', () {
    test('无数据返回空', () {
      expect(buildPageItems(1, 0), isEmpty);
    });

    test('只有一页时不放省略号', () {
      expect(buildPageItems(1, 1), [1]);
    });

    test('首页附近：末页恒出现，中间补省略号', () {
      expect(buildPageItems(1, 100), [1, 2, 3, null, 100]);
    });

    test('中间页：前后各补省略号', () {
      expect(buildPageItems(50, 100),
          [1, null, 48, 49, 50, 51, 52, null, 100]);
    });

    test('末页附近', () {
      expect(buildPageItems(100, 100), [1, null, 98, 99, 100]);
    });

    test('与首页/末页相邻时不插入省略号', () {
      expect(buildPageItems(2, 6), [1, 2, 3, 4, null, 6]);
      expect(buildPageItems(5, 6), [1, null, 3, 4, 5, 6]);
    });

    test('半径可调', () {
      expect(buildPageItems(10, 30, radius: 1), [1, null, 9, 10, 11, null, 30]);
    });
  });
}
