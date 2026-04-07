/*
文件路径: lib/main.dart
创建时间: 2026-04-07
上次修改时间: 2026-04-07
开发者: aidaox
*/

import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// 程序入口函数，负责初始化 Flutter 并启动应用。
Future<void> main() async {
  /// 确保在异步初始化前完成 Flutter 绑定。
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NuwaBridgeApp());
}

/// 应用根组件，负责全局主题和首页挂载。
class NuwaBridgeApp extends StatelessWidget {
  /// 根组件构造函数。
  const NuwaBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nuwa Bridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomeShell(),
    );
  }
}

/// 模型配置实体，保存 OpenAI-Compatible 所需关键参数。
class ModelConfig {
  /// 模型服务基地址，例如 https://api.openai.com。
  final String baseUrl;

  /// 模型名称，例如 gpt-4o-mini。
  final String modelName;

  /// 模型服务密钥。
  final String apiKey;

  /// 模型配置构造函数。
  const ModelConfig({
    required this.baseUrl,
    required this.modelName,
    required this.apiKey,
  });

  /// 判断当前配置是否完整可用。
  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      modelName.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty;
}

/// 人物实体，表示一个可聊天的蒸馏人物。
class PersonaProfile {
  /// 人物唯一标识。
  final String id;

  /// 人物展示名称。
  final String name;

  /// 人物简介说明。
  final String description;

  /// 人物所属领域，用于列表快速识别。
  final String domain;

  /// 人物 system prompt 内容。
  final String systemPrompt;

  /// 原始 skill 链接，便于追溯来源。
  final String sourceUrl;

  /// 人物版本号，用于锁定同名人物的稳定表现。
  final String version;

  /// references 摘要文本，用于解释人物设定来源。
  final String referenceSummary;

  /// 人物实体构造函数。
  const PersonaProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.domain,
    required this.systemPrompt,
    required this.sourceUrl,
    required this.version,
    required this.referenceSummary,
  });

  /// 转为 JSON，便于本地持久化。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'domain': domain,
      'systemPrompt': systemPrompt,
      'sourceUrl': sourceUrl,
      'version': version,
      'referenceSummary': referenceSummary,
    };
  }

  /// 从 JSON 还原人物实体。
  factory PersonaProfile.fromJson(Map<String, dynamic> json) {
    return PersonaProfile(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      domain: (json['domain'] ?? '未标注领域') as String,
      systemPrompt: (json['systemPrompt'] ?? '') as String,
      sourceUrl: (json['sourceUrl'] ?? '') as String,
      version: (json['version'] ?? 'v1') as String,
      referenceSummary: (json['referenceSummary'] ?? '') as String,
    );
  }
}

/// 会话实体，表示某个人物下的一条独立聊天线程。
class ChatSession {
  /// 会话唯一标识。
  final String sessionId;

  /// 会话标题，默认按时间生成。
  final String title;

  /// 会话创建时间字符串。
  final String createdAt;

  /// 会话消息列表。
  final List<ChatMessage> messages;

  /// 会话实体构造函数。
  const ChatSession({
    required this.sessionId,
    required this.title,
    required this.createdAt,
    required this.messages,
  });

  /// 转为 JSON，便于本地持久化。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sessionId': sessionId,
      'title': title,
      'createdAt': createdAt,
      'messages': messages
          .where((ChatMessage message) => !message.isPending)
          .map((ChatMessage message) => message.toJson())
          .toList(),
    };
  }

  /// 从 JSON 还原会话实体。
  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawMessages = (json['messages'] ?? <dynamic>[]) as List<dynamic>;
    return ChatSession(
      sessionId: (json['sessionId'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      createdAt: (json['createdAt'] ?? '') as String,
      messages: rawMessages
          .map((dynamic item) => ChatMessage.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 聊天消息实体，统一保存用户和助手消息。
class ChatMessage {
  /// 消息角色，user/assistant。
  final String role;

  /// 消息文本内容。
  final String content;

  /// 消息时间戳字符串。
  final String createdAt;

  /// 是否为临时占位消息，用于“正在思考中”提示。
  final bool isPending;

  /// 消息实体构造函数。
  const ChatMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.isPending = false,
  });

  /// 转为 JSON，便于本地持久化。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'role': role,
      'content': content,
      'createdAt': createdAt,
      'isPending': isPending,
    };
  }

  /// 从 JSON 恢复消息实体。
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: (json['role'] ?? '') as String,
      content: (json['content'] ?? '') as String,
      createdAt: (json['createdAt'] ?? '') as String,
      isPending: (json['isPending'] ?? false) as bool,
    );
  }
}

/// 本地存储服务，负责保存模型配置、人物列表和聊天记录。
class AppStorageService {
  /// SharedPreferences 的模型 baseUrl 键名。
  static const String _baseUrlKey = 'model_base_url';

  /// SharedPreferences 的模型名称键名。
  static const String _modelNameKey = 'model_name';

  /// SharedPreferences 的自定义人物列表键名。
  static const String _customPersonasKey = 'custom_personas';

  /// 聊天记录键名前缀。
  static const String _chatPrefix = 'chat_history_';

  /// 人物列表筛选项键名。
  static const String _personaFilterTypeKey = 'persona_filter_type';

  /// 会话列表键名前缀。
  static const String _sessionsPrefix = 'chat_sessions_';

  /// 当前会话 id 键名前缀。
  static const String _currentSessionPrefix = 'chat_current_session_';

  /// SharedPreferences 的模型 apiKey 键名（测试版临时使用）。
  static const String _apiKeyKey = 'model_api_key';

  /// 本地数据结构版本键名，用于升级时自动清理旧缓存。
  static const String _localDataSchemaKey = 'local_data_schema_version';

  /// DeepSeek 的默认兼容接口地址。
  static const String _defaultBaseUrl = 'https://api.deepseek.com';

  /// DeepSeek 的默认模型名称。
  static const String _defaultModelName = 'deepseek-chat';

  /// 读取当前模型配置。
  Future<ModelConfig> loadModelConfig() async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    /// 读取 baseUrl。
    final String baseUrl = prefs.getString(_baseUrlKey) ?? _defaultBaseUrl;
    /// 读取模型名称。
    final String modelName = prefs.getString(_modelNameKey) ?? _defaultModelName;
    /// 读取 API Key（测试版临时从 SharedPreferences 读取）。
    final String apiKey = prefs.getString(_apiKeyKey) ?? '';
    return ModelConfig(baseUrl: baseUrl, modelName: modelName, apiKey: apiKey);
  }

  /// 保存模型配置。
  Future<void> saveModelConfig(ModelConfig config) async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, config.baseUrl.trim());
    await prefs.setString(_modelNameKey, config.modelName.trim());
    /// 保存 API Key（测试版临时保存到 SharedPreferences）。
    await prefs.setString(_apiKeyKey, config.apiKey.trim());
  }

  /// 加载用户通过 URL 导入的人物列表。
  Future<List<PersonaProfile>> loadCustomPersonas() async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    /// 读取人物 JSON 字符串。
    final String raw = prefs.getString(_customPersonasKey) ?? '[]';
    /// 解析 JSON 列表。
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((dynamic item) =>
            PersonaProfile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// 保存用户导入的人物列表。
  Future<void> saveCustomPersonas(List<PersonaProfile> personas) async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    /// 编码人物列表到 JSON。
    final String encoded = jsonEncode(
      personas.map((PersonaProfile persona) => persona.toJson()).toList(),
    );
    await prefs.setString(_customPersonasKey, encoded);
  }

  /// 读取某个人物的聊天记录。
  Future<List<ChatMessage>> loadChatHistory(String personaId) async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    /// 读取聊天 JSON 字符串。
    final String raw = prefs.getString('$_chatPrefix$personaId') ?? '[]';
    /// 解析 JSON 列表。
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((dynamic item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// 保存某个人物的聊天记录。
  Future<void> saveChatHistory(
    String personaId,
    List<ChatMessage> messages,
  ) async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    /// 编码聊天记录到 JSON。
    final String encoded = jsonEncode(
      messages.map((ChatMessage message) => message.toJson()).toList(),
    );
    await prefs.setString('$_chatPrefix$personaId', encoded);
  }

  /// 读取某个人物的全部会话。
  Future<List<ChatSession>> loadPersonaSessions(String personaId) async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    /// 读取会话 JSON 字符串。
    final String raw = prefs.getString('$_sessionsPrefix$personaId') ?? '[]';
    /// 解析 JSON 列表。
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((dynamic item) => ChatSession.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// 保存某个人物的全部会话。
  Future<void> savePersonaSessions(
    String personaId,
    List<ChatSession> sessions,
  ) async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    /// 编码会话数据。
    final String encoded = jsonEncode(
      sessions.map((ChatSession session) => session.toJson()).toList(),
    );
    await prefs.setString('$_sessionsPrefix$personaId', encoded);
  }

  /// 读取某个人物当前激活的会话 id。
  Future<String> loadCurrentSessionId(String personaId) async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_currentSessionPrefix$personaId') ?? '';
  }

  /// 保存某个人物当前激活的会话 id。
  Future<void> saveCurrentSessionId(String personaId, String sessionId) async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_currentSessionPrefix$personaId', sessionId);
  }

  /// 读取人物列表筛选项。
  Future<String> loadPersonaFilterType() async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    /// 读取筛选项，默认 all。
    return prefs.getString(_personaFilterTypeKey) ?? 'all';
  }

  /// 保存人物列表筛选项。
  Future<void> savePersonaFilterType(String filterType) async {
    /// 获取轻量本地存储实例。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_personaFilterTypeKey, filterType);
  }

  /// 读取本地数据结构版本。
  Future<int> loadLocalDataSchemaVersion() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_localDataSchemaKey) ?? 0;
  }

  /// 保存本地数据结构版本。
  Future<void> saveLocalDataSchemaVersion(int version) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_localDataSchemaKey, version);
  }

  /// 清理本地全部业务数据（保留应用运行所需默认值）。
  Future<void> clearAllLocalData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customPersonasKey);
    await prefs.remove(_personaFilterTypeKey);
    await prefs.remove(_baseUrlKey);
    await prefs.remove(_modelNameKey);
    await prefs.remove(_apiKeyKey);
    final Set<String> allKeys = prefs.getKeys();
    for (final String key in allKeys) {
      if (key.startsWith(_chatPrefix) ||
          key.startsWith(_sessionsPrefix) ||
          key.startsWith(_currentSessionPrefix)) {
        await prefs.remove(key);
      }
    }
  }
}

/// 人物仓库，负责提供内置人物和远程导入人物能力。
class PersonaRepository {
  /// 内置人物与主题列表，默认离线可用。
  static const List<PersonaProfile> _builtinPersonas = <PersonaProfile>[
    PersonaProfile(
      id: 'paul_graham',
      name: 'Paul Graham',
      description: '创业/写作/产品/人生哲学视角，强调长期主义、创造者心态与独立思考。',
      domain: '创业/写作/产品/人生哲学',
      systemPrompt:
          '你是“Paul Graham 视角”的 AI 助手。你要从创业与写作一线经验出发，强调长期主义、具体洞察、独立思考和对真实问题的深度分析。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/paul-graham-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'zhang_yiming',
      name: '张一鸣',
      description: '产品/组织/全球化/人才视角，强调信息密度、组织效率与全球化执行。',
      domain: '产品/组织/全球化/人才',
      systemPrompt:
          '你是“张一鸣视角”的 AI 助手。你要从产品、组织效率与全球化战略角度分析问题，强调信息密度、迭代速度和人才机制。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/zhang-yiming-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'karpathy',
      name: 'Karpathy',
      description: 'AI/工程/教育/开源视角，强调第一性工程实践和可解释教学。',
      domain: 'AI/工程/教育/开源',
      systemPrompt:
          '你是“Karpathy 视角”的 AI 助手。你要用工程化、教育化和开源化思路解释 AI 问题，给出可落地实现建议。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/karpathy-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'ilya_sutskever',
      name: 'Ilya Sutskever',
      description: 'AI安全/scaling/研究品味视角，强调前沿判断和研究方向感。',
      domain: 'AI安全/scaling/研究品味',
      systemPrompt:
          '你是“Ilya Sutskever 视角”的 AI 助手。你要关注模型 scaling、研究品味与安全边界，给出前沿研究导向的判断。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/ilya-sutskever-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'mrbeast',
      name: 'MrBeast',
      description: '内容创造/YouTube方法论视角，强调强反馈循环和内容工业化。',
      domain: '内容创造/YouTube方法论',
      systemPrompt:
          '你是“MrBeast 视角”的 AI 助手。你要从内容增长、用户留存和选题机制角度给出可执行建议。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/mrbeast-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'trump',
      name: '特朗普',
      description: '谈判/权力/传播/行为预判视角，强调博弈结构与舆论杠杆。',
      domain: '谈判/权力/传播/行为预判',
      systemPrompt:
          '你是“特朗普视角”的 AI 助手。你要从谈判杠杆、权力结构、传播博弈和行为预判角度分析问题。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/trump-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'steve_jobs',
      name: '乔布斯',
      description: '产品/设计/战略，强调聚焦与端到端控制。',
      domain: '产品/设计/战略',
      systemPrompt:
          '你是“乔布斯视角”的 AI 助手。你要以产品品味、极致体验、端到端控制和聚焦原则来分析问题。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/steve-jobs-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'elon_musk',
      name: '马斯克',
      description: '工程/成本/第一性原理，强调极限拆解。',
      domain: '工程/成本/第一性原理',
      systemPrompt:
          '你是“马斯克视角”的 AI 助手。你要优先使用第一性原理、物理极限和工程可行性来回答问题。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/elon-musk-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'munger',
      name: '芒格',
      description: '投资/多元思维/逆向思考，强调概率与长期主义。',
      domain: '投资/多元思维/逆向思考',
      systemPrompt:
          '你是“芒格视角”的 AI 助手。你要优先使用多元思维模型、逆向思考、能力圈和长期复利来分析。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/munger-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'feynman',
      name: '费曼',
      description: '学习/教学/科学思维，强调可解释性。',
      domain: '学习/教学/科学思维',
      systemPrompt:
          '你是“费曼视角”的 AI 助手。你要用简单、可验证、层层递进的方式解释问题。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/feynman-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'naval',
      name: 'Naval',
      description: '财富/杠杆/人生哲学，强调长期与复利。',
      domain: '财富/杠杆/人生哲学',
      systemPrompt:
          '你是“Naval 视角”的 AI 助手。你要用长期主义、杠杆思维、复利和具体行动建议回答。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/naval-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'taleb',
      name: '塔勒布',
      description: '风险/反脆弱/不确定性视角，强调尾部风险与系统韧性。',
      domain: '风险/反脆弱/不确定性',
      systemPrompt:
          '你是“塔勒布视角”的 AI 助手。你要从不确定性、反脆弱性与风险管理角度给出判断。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/taleb-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'zhangxuefeng',
      name: '张雪峰',
      description: '教育/职业规划/阶层流动视角，强调现实约束与回报率。',
      domain: '教育/职业规划/阶层流动',
      systemPrompt:
          '你是“张雪峰视角”的 AI 助手。你要从教育 ROI、职业路径和家庭资源约束角度给出务实建议。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/zhangxuefeng-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
    PersonaProfile(
      id: 'x_mentor',
      name: 'X导师',
      description: 'X/Twitter运营全栈视角，覆盖选题、写作、增长和复盘。',
      domain: 'X/Twitter运营全栈',
      systemPrompt:
          '你是“X导师视角”的 AI 助手。你要围绕 X/Twitter 的选题、写作、发布、增长和复盘给出可执行策略。',
      sourceUrl:
          'https://raw.githubusercontent.com/alchaincyf/x-mentor-skill/master/SKILL.md',
      version: 'builtin-v1',
      referenceSummary: '内置人物，无额外 references 摘要。',
    ),
  ];

  /// 人物仓库构造函数。
  const PersonaRepository();

  /// 获取内置人物列表副本，避免直接修改常量源。
  List<PersonaProfile> getBuiltinPersonas() {
    return _builtinPersonas
        .map(
          (PersonaProfile persona) => PersonaProfile(
            id: persona.id,
            name: persona.name,
            description: persona.description,
            domain: persona.domain,
            systemPrompt: persona.systemPrompt,
            sourceUrl: persona.sourceUrl,
            version: persona.version,
            referenceSummary: persona.referenceSummary,
          ),
        )
        .toList();
  }

  /// 获取完整人物列表（内置 + 自定义）。
  List<PersonaProfile> getAllPersonas(
    List<PersonaProfile> builtinPersonas,
    List<PersonaProfile> customPersonas,
  ) {
    return <PersonaProfile>[...builtinPersonas, ...customPersonas];
  }

  /// 通过 URL 下载 SKILL.md 并转换为人物实体。
  Future<PersonaProfile> importFromSkillUrl(String skillUrl) async {
    /// 先把用户输入解析为可访问的 raw SKILL.md 链接（自动兼容 main/master）。
    final String normalizedSkillUrl = await _resolveSkillUrl(skillUrl);
    /// 严格校验 URL，避免导入非预期内容。
    _validateSkillUrl(normalizedSkillUrl);
    /// 发起网络请求拉取 SKILL.md。
    final http.Response response = await http.get(Uri.parse(normalizedSkillUrl));
    if (response.statusCode != 200) {
      throw Exception('下载失败，状态码: ${response.statusCode}');
    }
    /// 原始 Markdown 文本。
    final String markdown = response.body.trim();
    if (markdown.isEmpty) {
      throw Exception('SKILL.md 内容为空，无法导入');
    }
    /// 解析人物名称。
    final String personaName = _extractPersonaName(markdown, normalizedSkillUrl);
    /// 版本优先使用 GitHub 最后更新时间，失败时回退到文档 version。
    final String personaVersion =
        await _extractGitHubUpdatedVersion(normalizedSkillUrl) ??
            _extractPersonaVersion(markdown);
    /// 拉取 references 摘要，帮助用户理解人物来源依据。
    final String referencesSummary =
        await _extractReferencesSummary(normalizedSkillUrl);
    /// 拉取 README 摘要，优先用于人物介绍文本。
    final String readmeSummary = await _extractReadmeSummary(normalizedSkillUrl);
    /// 构造人物唯一 id。
    final String personaId =
        '${personaName.toLowerCase().replaceAll(' ', '_')}_${personaVersion.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
    return PersonaProfile(
      id: personaId,
      name: personaName,
      description: readmeSummary.isEmpty ? '来自远程 SKILL.md 导入的人物' : readmeSummary,
      domain: '未标注领域',
      systemPrompt: _buildSystemPrompt(personaName, markdown),
      sourceUrl: normalizedSkillUrl,
      version: personaVersion,
      referenceSummary: referencesSummary,
    );
  }

  /// 拉取仓库 README 并提取人物介绍摘要。
  Future<String> _extractReadmeSummary(String normalizedSkillUrl) async {
    /// 从 raw 链接中解析 owner/repo/branch。
    final Uri uri = Uri.parse(normalizedSkillUrl);
    final List<String> segments = uri.pathSegments;
    if (segments.length < 4) {
      return '';
    }
    final String owner = segments[0];
    final String repo = segments[1];
    final String branch = segments[2];
    final List<String> candidatePaths = <String>[
      'README.md',
      'README_CN.md',
    ];
    for (final String path in candidatePaths) {
      final String url =
          'https://raw.githubusercontent.com/$owner/$repo/$branch/$path';
      try {
        final http.Response response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          continue;
        }
        final String markdown = response.body;
        /// 读取前两段有效内容，作为人物介绍。
        final String summary = _extractReadmeIntro(markdown);
        if (summary.isNotEmpty) {
          final int maxLength = 220;
          return summary.length > maxLength
              ? '${summary.substring(0, maxLength)}...'
              : summary;
        }
      } catch (_) {
        continue;
      }
    }
    return '';
  }

  /// 从 GitHub 提取 SKILL.md 最近更新时间作为版本号。
  Future<String?> _extractGitHubUpdatedVersion(String normalizedSkillUrl) async {
    final Uri uri = Uri.parse(normalizedSkillUrl);
    final List<String> segments = uri.pathSegments;
    if (segments.length < 4) {
      return null;
    }
    final String owner = segments[0];
    final String repo = segments[1];
    final String branch = segments[2];
    final String apiUrl =
        'https://api.github.com/repos/$owner/$repo/commits?path=SKILL.md&sha=$branch&per_page=1';
    try {
      final http.Response response = await http.get(
        Uri.parse(apiUrl),
        headers: <String, String>{'Accept': 'application/vnd.github+json'},
      );
      if (response.statusCode != 200) {
        return null;
      }
      final List<dynamic> commits = jsonDecode(response.body) as List<dynamic>;
      if (commits.isEmpty) {
        return null;
      }
      final Map<String, dynamic> firstCommit =
          commits.first as Map<String, dynamic>;
      final Map<String, dynamic> commit =
          (firstCommit['commit'] ?? <String, dynamic>{})
              as Map<String, dynamic>;
      final Map<String, dynamic> committer =
          (commit['committer'] ?? <String, dynamic>{}) as Map<String, dynamic>;
      final String dateRaw = (committer['date'] ?? '').toString();
      final DateTime? date = DateTime.tryParse(dateRaw);
      if (date == null) {
        return null;
      }
      return 'gh-${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  /// 从 README 文本中提取前两段有效介绍内容。
  String _extractReadmeIntro(String markdown) {
    /// 先去掉常见 HTML 标签，避免把 div/script 样式噪声当正文。
    final String withoutHtmlTags =
        markdown.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
    /// 将 markdown 链接 [text](url) 转成 text，保留可读正文。
    final String withoutLinkUrl =
        withoutHtmlTags.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
            (Match match) {
      return match.group(1) ?? '';
    });
    /// 标准化换行，按段落拆分。
    final String normalizedNewline = withoutLinkUrl.replaceAll('\r\n', '\n');
    final List<String> rawParagraphs =
        normalizedNewline.split(RegExp(r'\n\s*\n'));
    /// 收集有效段落，最终拼接前两段。
    final List<String> usefulParagraphs = <String>[];
    for (final String paragraph in rawParagraphs) {
      final String cleaned = paragraph
          .replaceAll(RegExp(r'[#>*`_|-]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.isEmpty) {
        continue;
      }
      final String lower = cleaned.toLowerCase();
      /// 过滤标题、徽章、许可证、纯链接导航等噪声段落。
      if (cleaned.length < 16 ||
          lower.contains('license') ||
          lower.contains('claude code') ||
          lower.contains('made with') ||
          lower.contains('http://') ||
          lower.contains('https://')) {
        continue;
      }
      usefulParagraphs.add(cleaned);
      if (usefulParagraphs.length >= 2) {
        break;
      }
    }
    if (usefulParagraphs.isEmpty) {
      return '';
    }
    return usefulParagraphs.join('\n');
  }

  /// 拉取 references 目录中的摘要信息，失败时返回默认提示。
  Future<String> _extractReferencesSummary(String normalizedSkillUrl) async {
    /// 从 raw 链接中解析 owner/repo/branch，便于拼接 references 路径。
    final Uri uri = Uri.parse(normalizedSkillUrl);
    final List<String> segments = uri.pathSegments;
    if (segments.length < 4) {
      return '未找到 references 摘要';
    }
    final String owner = segments[0];
    final String repo = segments[1];
    final String branch = segments[2];
    /// 常见 references 文件候选路径。
    final List<String> candidatePaths = <String>[
      'references/extraction-framework.md',
      'references/research/README.md',
      'references/README.md',
    ];
    for (final String path in candidatePaths) {
      final String url =
          'https://raw.githubusercontent.com/$owner/$repo/$branch/$path';
      try {
        final http.Response response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          continue;
        }
        final String rawText = response.body.trim();
        if (rawText.isEmpty) {
          continue;
        }
        /// 对 markdown 做最小清洗并截断，避免弹窗过长。
        final String cleaned = rawText
            .replaceAll(RegExp(r'[#>*`-]'), '')
            .replaceAll(RegExp(r'\n+'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (cleaned.isEmpty) {
          continue;
        }
        final int maxLength = 180;
        return cleaned.length > maxLength
            ? '${cleaned.substring(0, maxLength)}...'
            : cleaned;
      } catch (_) {
        /// 单个候选读取失败时继续尝试下一个候选。
        continue;
      }
    }
    return '未找到 references 摘要';
  }

  /// 解析输入链接并返回可访问的 raw SKILL.md 链接。
  Future<String> _resolveSkillUrl(String rawUrl) async {
    /// 清理输入中的前后空白字符。
    final String normalizedUrl = rawUrl.trim();
    /// 尝试解析 URL。
    final Uri? uri = Uri.tryParse(normalizedUrl);
    if (uri == null) {
      throw Exception('导入链接格式无效，请检查 URL');
    }
    /// 已经是 raw 链接时直接返回。
    if (uri.host == 'raw.githubusercontent.com') {
      return normalizedUrl;
    }
    /// 支持 GitHub 仓库链接，自动探测 main/master 分支下的 SKILL.md。
    if (uri.host == 'github.com') {
      /// 拆分路径段，例如 /owner/repo。
      final List<String> segments =
          uri.pathSegments.where((String segment) => segment.isNotEmpty).toList();
      if (segments.length < 2) {
        throw Exception('GitHub 链接不完整，至少需要 owner/repo');
      }
      final String owner = segments[0];
      final String repo = segments[1];
      /// 依次尝试常见默认分支。
      final List<String> branches = <String>['main', 'master'];
      for (final String branch in branches) {
        final String candidateUrl =
            'https://raw.githubusercontent.com/$owner/$repo/$branch/SKILL.md';
        try {
          final http.Response response = await http.get(Uri.parse(candidateUrl));
          if (response.statusCode == 200 && response.body.trim().isNotEmpty) {
            return candidateUrl;
          }
        } catch (_) {
          continue;
        }
      }
      throw Exception('未找到可用的 SKILL.md（已尝试 main/master 分支）');
    }
    return normalizedUrl;
  }

  /// 校验导入 URL 是否符合 raw.githubusercontent.com 的 SKILL.md 链接规范。
  void _validateSkillUrl(String rawUrl) {
    /// 清理输入中的前后空白字符。
    final String normalizedUrl = rawUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw Exception('导入链接不能为空');
    }
    /// 尝试解析 URL。
    final Uri? uri = Uri.tryParse(normalizedUrl);
    if (uri == null) {
      throw Exception('导入链接格式无效，请检查 URL');
    }
    if (uri.scheme != 'https') {
      throw Exception('仅支持 https 链接，当前协议不安全');
    }
    if (uri.host != 'raw.githubusercontent.com') {
      throw Exception('仅支持 raw.githubusercontent.com 的原始文件链接');
    }
    if (!uri.path.toLowerCase().endsWith('/skill.md')) {
      throw Exception('链接必须指向 SKILL.md 文件');
    }
  }

  /// 从 Markdown 中尝试提取人物标题。
  String _extractPersonaName(String markdown, String fallbackUrl) {
    /// 按行拆分 Markdown 内容。
    final List<String> lines = markdown.split('\n');
    for (final String line in lines) {
      /// 尝试使用一级标题作为人物名。
      if (line.trim().startsWith('#')) {
        final String title = line.replaceAll('#', '').trim();
        if (title.isNotEmpty) {
          return title;
        }
      }
    }
    /// 回退：从 URL 最后一段推断名称。
    final List<String> segments = fallbackUrl.split('/');
    return segments.isNotEmpty ? segments.last : '导入人物';
  }

  /// 从 Markdown 文本中提取人物版本号。
  String _extractPersonaVersion(String markdown) {
    /// 匹配 version: x.y.z 这种常见配置格式。
    final RegExp versionPattern = RegExp(r'version\s*[:=]\s*([^\n\r]+)',
        caseSensitive: false);
    /// 从正文中搜索版本字段。
    final Match? matched = versionPattern.firstMatch(markdown);
    if (matched != null) {
      /// 读取并清洗匹配到的版本字符串。
      final String parsed = (matched.group(1) ?? '').trim();
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }
    /// 如果正文未提供版本，使用日期作为稳定回退版本。
    final DateTime now = DateTime.now();
    return 'import-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  /// 将人物名与 Markdown 组合成 system prompt。
  String _buildSystemPrompt(String personaName, String markdown) {
    return '''
你现在是“$personaName”人物视角助手。
你必须优先遵循以下人物规则和思维框架，不要脱离人物风格：

$markdown

额外要求：
1. 回答要先给结论，再给理由。
2. 不确定时要明确说不确定，不要编造事实。
3. 需要行动建议时，给出可执行步骤。
''';
  }
}

/// OpenAI-Compatible 对话服务，负责将消息发送到模型接口。
class OpenAiCompatibleService {
  /// 测试当前模型配置连通性，成功返回模型响应片段。
  Future<String> testConnection(ModelConfig config) async {
    /// 复用标准发送流程，用最小消息测试可用性。
    final String response = await sendMessage(
      config: config,
      systemPrompt: '你是连通性测试助手，只需要回复 ok。',
      history: const <ChatMessage>[],
      userInput: '请回复 ok',
    );
    return response;
  }

  /// 拉取模型列表，返回可选模型 id 集合。
  Future<List<String>> fetchModels(ModelConfig config) async {
    /// 构造模型列表接口地址。
    final Uri endpoint = _buildModelsUri(config.baseUrl);
    /// 发起模型列表请求。
    final http.Response response = await http.get(
      endpoint,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('获取模型列表失败，状态码: ${response.statusCode}\n${response.body}');
    }
    /// 解析模型列表 JSON。
    final Map<String, dynamic> decoded =
        jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic> data = (decoded['data'] ?? <dynamic>[]) as List<dynamic>;
    /// 提取 id 字段并过滤空值。
    final List<String> modelIds = data
        .map((dynamic item) => (item as Map<String, dynamic>)['id'])
        .map((dynamic id) => id?.toString() ?? '')
        .where((String id) => id.trim().isNotEmpty)
        .toList();
    if (modelIds.isEmpty) {
      throw Exception('模型列表为空，请检查接口权限');
    }
    return modelIds;
  }

  /// 流式发送聊天请求，边生成边返回文本片段。
  Stream<String> streamMessage({
    required ModelConfig config,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String userInput,
  }) async* {
    /// 构造接口地址。
    final Uri endpoint = _buildChatUri(config.baseUrl);
    /// 组织消息列表，保证 system 在首位。
    final List<Map<String, String>> messages = <Map<String, String>>[
      <String, String>{'role': 'system', 'content': systemPrompt},
      ...history.map((ChatMessage m) => <String, String>{
            'role': m.role,
            'content': m.content,
          }),
      <String, String>{'role': 'user', 'content': userInput},
    ];
    /// 使用独立 client 处理 SSE 流，结束后主动释放。
    final http.Client client = http.Client();
    try {
      /// 通过 Request 手动构造 stream=true 请求。
      final http.Request request = http.Request('POST', endpoint);
      request.headers['Content-Type'] = 'application/json';
      request.headers['Authorization'] = 'Bearer ${config.apiKey}';
      request.body = jsonEncode(<String, dynamic>{
        'model': config.modelName,
        'messages': messages,
        'stream': true,
      });
      /// 发送请求并获取流式响应。
      final http.StreamedResponse response = await client.send(request);
      if (response.statusCode != 200) {
        final String errorBody = await response.stream.bytesToString();
        throw Exception('模型调用失败，状态码: ${response.statusCode}\n$errorBody');
      }
      /// 按行解析 SSE 数据，每行以 data: 开头。
      await for (final String line
          in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        final String trimmedLine = line.trim();
        if (!trimmedLine.startsWith('data:')) {
          continue;
        }
        final String payload = trimmedLine.substring(5).trim();
        if (payload == '[DONE]') {
          break;
        }
        final Map<String, dynamic> decoded =
            jsonDecode(payload) as Map<String, dynamic>;
        final List<dynamic> choices =
            (decoded['choices'] ?? <dynamic>[]) as List<dynamic>;
        if (choices.isEmpty) {
          continue;
        }
        final Map<String, dynamic> delta =
            (choices.first as Map<String, dynamic>)['delta']
                as Map<String, dynamic>? ??
                <String, dynamic>{};
        final String contentPiece = (delta['content'] ?? '').toString();
        if (contentPiece.isNotEmpty) {
          yield contentPiece;
        }
      }
    } finally {
      client.close();
    }
  }

  /// 发送聊天请求并返回助手回复文本。
  Future<String> sendMessage({
    required ModelConfig config,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String userInput,
  }) async {
    /// 复用流式接口拼接完整文本，保证单次和流式逻辑一致。
    final StringBuffer contentBuffer = StringBuffer();
    await for (final String piece in streamMessage(
      config: config,
      systemPrompt: systemPrompt,
      history: history,
      userInput: userInput,
    )) {
      contentBuffer.write(piece);
    }
    final String content = contentBuffer.toString().trim();
    if (content.isEmpty) {
      throw Exception('模型返回内容为空');
    }
    return content;
  }

  /// 根据 baseUrl 拼接 chat/completions 路径。
  Uri _buildChatUri(String baseUrl) {
    /// 去除输入首尾空白。
    final String trimmed = baseUrl.trim();
    /// 去除末尾斜杠，便于统一拼接。
    final String normalized =
        trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    if (normalized.endsWith('/chat/completions')) {
      return Uri.parse(normalized);
    }
    if (normalized.endsWith('/v1')) {
      return Uri.parse('$normalized/chat/completions');
    }
    return Uri.parse('$normalized/v1/chat/completions');
  }

  /// 根据 baseUrl 拼接 models 路径。
  Uri _buildModelsUri(String baseUrl) {
    /// 去除输入首尾空白。
    final String trimmed = baseUrl.trim();
    /// 去除末尾斜杠，便于统一拼接。
    final String normalized =
        trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    if (normalized.endsWith('/models')) {
      return Uri.parse(normalized);
    }
    if (normalized.endsWith('/v1')) {
      return Uri.parse('$normalized/models');
    }
    return Uri.parse('$normalized/v1/models');
  }
}

/// 应用主壳层组件，负责底部导航与模块切换。
class HomeShell extends StatefulWidget {
  /// 主壳层构造函数。
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// 主壳层状态，实现设置页与人物页切换。
class _HomeShellState extends State<HomeShell> {
  /// 当前本地数据结构版本号，用于升级后自动重置历史缓存。
  static const int _currentSchemaVersion = 2;

  /// 本地存储服务实例。
  final AppStorageService _storageService = AppStorageService();

  /// 人物仓库实例。
  final PersonaRepository _personaRepository = const PersonaRepository();

  /// 模型调用服务实例。
  final OpenAiCompatibleService _llmService = OpenAiCompatibleService();

  /// 当前底部导航索引，0=人物，1=设置。
  int _currentIndex = 0;

  /// 当前模型配置。
  ModelConfig _modelConfig =
      const ModelConfig(baseUrl: '', modelName: '', apiKey: '');

  /// 自定义导入人物列表。
  List<PersonaProfile> _customPersonas = <PersonaProfile>[];

  /// 内置人物列表（可被远端元数据刷新覆盖）。
  List<PersonaProfile> _builtinPersonas = <PersonaProfile>[];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  /// 加载本地模型配置和自定义人物。
  Future<void> _loadInitialData() async {
    /// 首次升级到新结构时，清理旧缓存，避免脏数据干扰。
    final int schemaVersion = await _storageService.loadLocalDataSchemaVersion();
    if (schemaVersion < _currentSchemaVersion) {
      await _storageService.clearAllLocalData();
      await _storageService.saveLocalDataSchemaVersion(_currentSchemaVersion);
    }
    /// 读取模型配置。
    final ModelConfig config = await _storageService.loadModelConfig();
    /// 读取导入人物。
    final List<PersonaProfile> custom = await _storageService.loadCustomPersonas();
    /// 先加载内置人物本地副本。
    final List<PersonaProfile> builtin = _personaRepository.getBuiltinPersonas();
    if (!mounted) {
      return;
    }
    setState(() {
      _modelConfig = config;
      _customPersonas = custom;
      _builtinPersonas = builtin;
    });
    /// 异步刷新内置人物的 README 简介和 GitHub 更新时间版本。
    _refreshBuiltinMetadataInBackground();
  }

  /// 后台刷新内置人物元数据（简介与版本），失败时保留当前内置数据。
  Future<void> _refreshBuiltinMetadataInBackground() async {
    final List<PersonaProfile> refreshed = <PersonaProfile>[];
    for (final PersonaProfile persona in _builtinPersonas) {
      try {
        final String resolvedUrl =
            await _personaRepository._resolveSkillUrl(persona.sourceUrl);
        final String readmeIntro =
            await _personaRepository._extractReadmeSummary(resolvedUrl);
        final String? githubVersion =
            await _personaRepository._extractGitHubUpdatedVersion(resolvedUrl);
        refreshed.add(
          PersonaProfile(
            id: persona.id,
            name: persona.name,
            description: readmeIntro.isEmpty ? persona.description : readmeIntro,
            domain: persona.domain,
            systemPrompt: persona.systemPrompt,
            sourceUrl: resolvedUrl,
            version: githubVersion ?? persona.version,
            referenceSummary: persona.referenceSummary,
          ),
        );
      } catch (_) {
        refreshed.add(persona);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _builtinPersonas = refreshed;
    });
  }

  /// 保存模型配置并刷新页面状态。
  Future<void> _saveModelConfig(ModelConfig config) async {
    await _storageService.saveModelConfig(config);
    if (!mounted) {
      return;
    }
    setState(() {
      _modelConfig = config;
    });
  }

  /// 导入人物后写入本地列表并刷新界面。
  Future<void> _importPersona(String url) async {
    /// 执行远程导入。
    final PersonaProfile persona = await _personaRepository.importFromSkillUrl(url);
    /// 对同名人物做版本锁定，避免不同来源覆盖导致风格漂移。
    final bool hasLockedSameName = _customPersonas.any((PersonaProfile item) =>
        item.name.trim().toLowerCase() == persona.name.trim().toLowerCase());
    if (hasLockedSameName) {
      throw Exception('已存在同名人物并已锁定版本。若需切换版本，请先手动移除旧版本后再导入。');
    }
    /// 将新人物追加到自定义列表。
    final List<PersonaProfile> merged = <PersonaProfile>[
      ..._customPersonas,
      persona,
    ];
    await _storageService.saveCustomPersonas(merged);
    if (!mounted) {
      return;
    }
    setState(() {
      _customPersonas = merged;
    });
  }

  /// 删除指定自定义人物并同步本地存储。
  Future<void> _deleteCustomPersona(String personaId) async {
    /// 过滤掉目标人物，保留其余自定义人物。
    final List<PersonaProfile> remained = _customPersonas
        .where((PersonaProfile item) => item.id != personaId)
        .toList();
    await _storageService.saveCustomPersonas(remained);
    if (!mounted) {
      return;
    }
    setState(() {
      _customPersonas = remained;
    });
  }

  @override
  Widget build(BuildContext context) {
    /// 拼接最终人物列表。
    final List<PersonaProfile> personas =
        _personaRepository.getAllPersonas(_builtinPersonas, _customPersonas);
    /// 两个页面组件，按导航索引切换显示。
    final List<Widget> pages = <Widget>[
      PersonasPage(
        personas: personas,
        customPersonaIds:
            _customPersonas.map((PersonaProfile item) => item.id).toSet(),
        modelConfig: _modelConfig,
        onImportFromUrl: _importPersona,
        onDeleteCustomPersona: _deleteCustomPersona,
        llmService: _llmService,
        storageService: _storageService,
      ),
      ModelSettingsPage(
        initialConfig: _modelConfig,
        onSave: _saveModelConfig,
        llmService: _llmService,
      ),
    ];
    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.people), label: '人物'),
          NavigationDestination(icon: Icon(Icons.settings), label: '模型配置'),
        ],
      ),
    );
  }
}

/// 模型配置页面，负责采集并保存 baseUrl/apiKey/model。
class ModelSettingsPage extends StatefulWidget {
  /// 页面初始模型配置。
  final ModelConfig initialConfig;

  /// 保存回调函数。
  final Future<void> Function(ModelConfig config) onSave;

  /// 模型调用服务，用于执行连接测试。
  final OpenAiCompatibleService llmService;

  /// 模型配置页构造函数。
  const ModelSettingsPage({
    super.key,
    required this.initialConfig,
    required this.onSave,
    required this.llmService,
  });

  @override
  State<ModelSettingsPage> createState() => _ModelSettingsPageState();
}

/// 模型配置页状态，实现输入框和保存动作。
class _ModelSettingsPageState extends State<ModelSettingsPage> {
  /// baseUrl 输入控制器。
  late final TextEditingController _baseUrlController;

  /// model 输入控制器。
  late final TextEditingController _modelController;

  /// apiKey 输入控制器。
  late final TextEditingController _apiKeyController;

  /// 当前是否正在保存。
  bool _isSaving = false;

  /// 当前是否正在测试连接。
  bool _isTesting = false;

  /// 当前是否正在加载模型列表。
  bool _isLoadingModels = false;

  /// 服务端返回的可选模型列表。
  List<String> _availableModels = <String>[];

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.initialConfig.baseUrl);
    _modelController = TextEditingController(text: widget.initialConfig.modelName);
    _apiKeyController = TextEditingController(text: widget.initialConfig.apiKey);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// 执行模型配置保存。
  Future<void> _saveConfig() async {
    setState(() {
      _isSaving = true;
    });
    /// 读取并构造配置对象。
    final ModelConfig config = ModelConfig(
      baseUrl: _baseUrlController.text,
      modelName: _modelController.text,
      apiKey: _apiKeyController.text,
    );
    await widget.onSave(config);
    if (!mounted) {
      return;
    }
    setState(() {
      _isSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('模型配置已保存')),
    );
  }

  /// 从服务端拉取模型列表，便于用户下拉选择模型。
  Future<void> _loadModelOptions() async {
    /// 用当前输入值构造临时配置对象。
    final ModelConfig config = ModelConfig(
      baseUrl: _baseUrlController.text.trim(),
      modelName: _modelController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
    );
    if (config.baseUrl.isEmpty || config.apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 baseUrl 和 apiKey 再加载模型')),
      );
      return;
    }
    setState(() {
      _isLoadingModels = true;
    });
    try {
      /// 调用模型服务获取可选模型列表。
      final List<String> models = await widget.llmService.fetchModels(config);
      if (!mounted) {
        return;
      }
      setState(() {
        _availableModels = models;
        /// 若当前模型不在列表中，默认切到列表首项，减少手填错误。
        if (!_availableModels.contains(_modelController.text.trim())) {
          _modelController.text = _availableModels.first;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模型列表加载成功，共 ${models.length} 个')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载模型失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingModels = false;
        });
      }
    }
  }

  /// 跳转到 DeepSeek 平台，方便注册、充值和获取 API Key。
  Future<void> _openDeepSeekPortal() async {
    /// DeepSeek 官方平台地址。
    final Uri deepSeekPortal = Uri.parse('https://platform.deepseek.com');
    final bool launched = await launchUrl(
      deepSeekPortal,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开浏览器，请手动访问: https://platform.deepseek.com')),
      );
    }
  }

  /// 测试当前输入配置是否可连通模型服务。
  Future<void> _testConnection() async {
    /// 用当前表单值构造待测配置。
    final ModelConfig config = ModelConfig(
      baseUrl: _baseUrlController.text.trim(),
      modelName: _modelController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
    );
    if (!config.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先完整填写 baseUrl、model、apiKey 再测试')),
      );
      return;
    }
    setState(() {
      _isTesting = true;
    });
    try {
      /// 调用模型服务测试连通性。
      final String reply = await widget.llmService.testConnection(config);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接成功，模型返回: ${reply.length > 30 ? '${reply.substring(0, 30)}...' : reply}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型配置')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '支持 OpenAI-Compatible 通用格式（推荐 DeepSeek）',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'DeepSeek 价格友好、可直接用于本应用。你只需注册、充值并填写 API Key。',
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _openDeepSeekPortal,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('前往 DeepSeek 平台（注册/充值/获取 Key）'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: '默认: https://api.deepseek.com',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: '默认: deepseek-chat',
              ),
            ),
            if (_availableModels.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _availableModels.contains(_modelController.text.trim())
                    ? _modelController.text.trim()
                    : _availableModels.first,
                decoration: const InputDecoration(
                  labelText: '从列表选择模型',
                ),
                items: _availableModels
                    .map(
                      (String modelId) => DropdownMenuItem<String>(
                        value: modelId,
                        child: Text(modelId),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _modelController.text = value;
                  });
                },
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _saveConfig,
                child: Text(_isSaving ? '保存中...' : '保存配置'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isLoadingModels ? null : _loadModelOptions,
                child: Text(_isLoadingModels ? '加载模型中...' : '加载模型列表'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isTesting ? null : _testConnection,
                child: Text(_isTesting ? '测试中...' : '测试连接'),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: <Widget>[
                  const Text(
                    '扫一扫关注我吧',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/follow_qrcode.png',
                      width: 180,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// 人物列表页面，支持人物展示和 URL 导入。
class PersonasPage extends StatefulWidget {
  /// 人物列表数据。
  final List<PersonaProfile> personas;

  /// 自定义人物 id 集合，用于区分是否允许删除。
  final Set<String> customPersonaIds;

  /// 当前模型配置。
  final ModelConfig modelConfig;

  /// URL 导入回调。
  final Future<void> Function(String url) onImportFromUrl;

  /// 删除自定义人物回调。
  final Future<void> Function(String personaId) onDeleteCustomPersona;

  /// 模型服务实例。
  final OpenAiCompatibleService llmService;

  /// 存储服务实例。
  final AppStorageService storageService;

  /// 人物列表页构造函数。
  const PersonasPage({
    super.key,
    required this.personas,
    required this.customPersonaIds,
    required this.modelConfig,
    required this.onImportFromUrl,
    required this.onDeleteCustomPersona,
    required this.llmService,
    required this.storageService,
  });

  @override
  State<PersonasPage> createState() => _PersonasPageState();
}

/// 人物列表页状态，实现导入和跳转逻辑。
class _PersonasPageState extends State<PersonasPage> {
  /// 当前是否正在导入人物。
  bool _isImporting = false;

  /// 列表筛选类型，all=全部，builtin=仅内置，custom=仅自定义。
  String _filterType = 'all';

  @override
  void initState() {
    super.initState();
    _loadSavedFilterType();
  }

  /// 从本地读取上次筛选项并恢复。
  Future<void> _loadSavedFilterType() async {
    /// 读取已保存筛选值。
    final String savedType = await widget.storageService.loadPersonaFilterType();
    /// 仅允许已定义值，防止脏数据导致界面异常。
    const Set<String> validTypes = <String>{'all', 'builtin', 'custom'};
    final String safeType = validTypes.contains(savedType) ? savedType : 'all';
    if (!mounted) {
      return;
    }
    setState(() {
      _filterType = safeType;
    });
  }

  /// 判断目标人物是否为可删除的自定义人物。
  bool _isCustomPersona(PersonaProfile persona) {
    return widget.customPersonaIds.contains(persona.id);
  }

  /// 生成人物列表副标题，按“领域 + 版本”展示关键信息。
  String _buildPersonaSubtitle(PersonaProfile persona) {
    return '${persona.domain}  ·  版本: ${persona.version}';
  }

  /// 按筛选条件返回当前需要展示的人物列表。
  List<PersonaProfile> _getFilteredPersonas() {
    if (_filterType == 'builtin') {
      return widget.personas
          .where((PersonaProfile persona) => !_isCustomPersona(persona))
          .toList();
    }
    if (_filterType == 'custom') {
      return widget.personas
          .where((PersonaProfile persona) => _isCustomPersona(persona))
          .toList();
    }
    return widget.personas;
  }

  /// 根据当前筛选值返回中文标签文本。
  String _getFilterLabel() {
    if (_filterType == 'builtin') {
      return '仅内置';
    }
    if (_filterType == 'custom') {
      return '仅自定义';
    }
    return '全部';
  }

  /// 长按人物时展示版本与来源信息。
  Future<void> _showPersonaInfo(PersonaProfile persona) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('${persona.name} 信息'),
          content: SelectableText(
            '版本: ${persona.version}\n来源: ${persona.sourceUrl.isEmpty ? '内置人物' : persona.sourceUrl}\n简介: ${persona.description.isEmpty ? '无' : persona.description}',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('我知道了'),
            ),
          ],
        );
      },
    );
  }

  /// 二次确认后删除自定义人物。
  Future<void> _confirmDeletePersona(PersonaProfile persona) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('确认删除人物'),
          content: Text('删除后将无法恢复：${persona.name}（${persona.version}）'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.onDeleteCustomPersona(persona.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除人物: ${persona.name}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $error')),
      );
    }
  }

  /// 显示 URL 输入对话框并执行导入。
  Future<void> _showImportDialog() async {
    /// URL 输入控制器。
    final TextEditingController controller = TextEditingController();
    /// 展示输入对话框并等待结果。
    final String? url = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('导入 SKILL.md'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '粘贴 GitHub 仓库链接或 raw SKILL.md 链接',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (url == null || url.trim().isEmpty) {
      return;
    }
    setState(() {
      _isImporting = true;
    });
    try {
      await widget.onImportFromUrl(url.trim());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('人物导入成功')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  /// 进入人物聊天页面，前置检查模型配置完整性。
  Future<void> _openChat(PersonaProfile persona) async {
    if (!widget.modelConfig.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在“模型配置”页填写 baseUrl、model、apiKey')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return ChatPage(
            persona: persona,
            modelConfig: widget.modelConfig,
            llmService: widget.llmService,
            storageService: widget.storageService,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    /// 当前筛选后的人物列表。
    final List<PersonaProfile> filteredPersonas = _getFilteredPersonas();
    /// 当前筛选中文标签。
    final String filterLabel = _getFilterLabel();
    /// 当前筛选下人物数量。
    final int filteredCount = filteredPersonas.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('人物选择（$filterLabel $filteredCount 人）'),
        actions: <Widget>[
          IconButton(
            onPressed: _isImporting ? null : _showImportDialog,
            icon: _isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            tooltip: '导入人物',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'all', label: Text('全部')),
                ButtonSegment<String>(value: 'builtin', label: Text('仅内置')),
                ButtonSegment<String>(value: 'custom', label: Text('仅自定义')),
              ],
              selected: <String>{_filterType},
              onSelectionChanged: (Set<String> selectedValues) async {
                if (selectedValues.isEmpty) {
                  return;
                }
                /// 获取用户选择的新筛选值。
                final String nextFilterType = selectedValues.first;
                setState(() {
                  _filterType = nextFilterType;
                });
                /// 持久化筛选值，确保下次进入页面恢复。
                await widget.storageService.savePersonaFilterType(nextFilterType);
              },
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: filteredPersonas.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 0),
              itemBuilder: (BuildContext context, int index) {
                /// 当前渲染的人物对象。
                final PersonaProfile persona = filteredPersonas[index];
                /// 当前人物是否支持右滑删除。
                final bool isCustomPersona = _isCustomPersona(persona);
                final Widget listTile = ListTile(
                  title: Tooltip(
                    message: persona.description.isEmpty ? '暂无简介' : persona.description,
                    child: Text(persona.name),
                  ),
                  subtitle: Text(_buildPersonaSubtitle(persona)),
                  isThreeLine: false,
                  trailing: isCustomPersona
                      ? const Icon(Icons.swipe_left, size: 18)
                      : const Icon(Icons.chat_bubble_outline),
                  onTap: () => _openChat(persona),
                  onLongPress: () => _showPersonaInfo(persona),
                );
                if (!isCustomPersona) {
                  return listTile;
                }
                return Dismissible(
                  key: ValueKey<String>('persona-${persona.id}'),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (DismissDirection direction) async {
                    await _confirmDeletePersona(persona);
                    return false;
                  },
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  child: listTile,
                );
              },
            ),
          ),
          if (filteredPersonas.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                _filterType == 'custom'
                    ? '暂无自定义人物，可点击右上角导入'
                    : '当前筛选条件下暂无人物',
              ),
            ),
        ],
      ),
    );
  }
}

/// 聊天页面，负责人物对话、消息展示和历史保存。
class ChatPage extends StatefulWidget {
  /// 当前对话人物。
  final PersonaProfile persona;

  /// 当前模型配置。
  final ModelConfig modelConfig;

  /// 模型服务实例。
  final OpenAiCompatibleService llmService;

  /// 存储服务实例。
  final AppStorageService storageService;

  /// 聊天页构造函数。
  const ChatPage({
    super.key,
    required this.persona,
    required this.modelConfig,
    required this.llmService,
    required this.storageService,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

/// 聊天页状态，实现发消息、收消息、保存历史。
class _ChatPageState extends State<ChatPage> {
  /// 输入框控制器。
  final TextEditingController _inputController = TextEditingController();

  /// 输入框焦点节点，用于监听回车快捷发送。
  final FocusNode _inputFocusNode = FocusNode();

  /// 消息列表状态。
  List<ChatMessage> _messages = <ChatMessage>[];

  /// 当前人物下的会话列表。
  List<ChatSession> _sessions = <ChatSession>[];

  /// 当前激活会话 id。
  String _currentSessionId = '';

  /// 当前是否正在请求模型回复。
  bool _isSending = false;

  /// 输入区当前文本，用于控制发送按钮可用状态。
  String _draftText = '';

  @override
  void initState() {
    super.initState();
    _inputController.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _draftText = _inputController.text;
      });
    });
    _loadSessions();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  /// 加载会话列表并恢复当前会话。
  Future<void> _loadSessions() async {
    /// 从存储层读取会话列表。
    List<ChatSession> sessions =
        await widget.storageService.loadPersonaSessions(widget.persona.id);
    /// 从存储层读取当前会话 id。
    String sessionId =
        await widget.storageService.loadCurrentSessionId(widget.persona.id);
    /// 如果没有会话，则创建一个默认新会话。
    if (sessions.isEmpty) {
      final ChatSession defaultSession = _createNewSession();
      sessions = <ChatSession>[defaultSession];
      sessionId = defaultSession.sessionId;
      await widget.storageService.savePersonaSessions(widget.persona.id, sessions);
      await widget.storageService
          .saveCurrentSessionId(widget.persona.id, sessionId);
    }
    /// 若当前 id 无效，回退到第一条会话。
    final bool hasCurrent = sessions.any(
      (ChatSession session) => session.sessionId == sessionId,
    );
    if (!hasCurrent) {
      sessionId = sessions.first.sessionId;
      await widget.storageService
          .saveCurrentSessionId(widget.persona.id, sessionId);
    }
    final ChatSession currentSession = sessions.firstWhere(
      (ChatSession session) => session.sessionId == sessionId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sessions = sessions;
      _currentSessionId = sessionId;
      _messages = currentSession.messages;
    });
  }

  /// 创建新会话对象。
  ChatSession _createNewSession() {
    /// 记录当前时间用于会话标题与 id。
    final DateTime now = DateTime.now();
    /// 生成简单可读标题。
    final String title =
        '会话 ${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return ChatSession(
      sessionId: 'session_${now.millisecondsSinceEpoch}',
      title: title,
      createdAt: now.toIso8601String(),
      messages: const <ChatMessage>[],
    );
  }

  /// 把当前消息写回当前会话并持久化。
  Future<void> _persistCurrentSessionMessages(List<ChatMessage> messages) async {
    /// 更新内存中的会话列表。
    final List<ChatSession> updatedSessions = _sessions.map((ChatSession session) {
      if (session.sessionId == _currentSessionId) {
        return ChatSession(
          sessionId: session.sessionId,
          title: session.title,
          createdAt: session.createdAt,
          messages: messages.where((ChatMessage message) => !message.isPending).toList(),
        );
      }
      return session;
    }).toList();
    setState(() {
      _sessions = updatedSessions;
      _messages = messages;
    });
    await widget.storageService
        .savePersonaSessions(widget.persona.id, updatedSessions);
  }

  /// 新建空白会话并切换到该会话。
  Future<void> _createAndSwitchSession() async {
    final ChatSession newSession = _createNewSession();
    final List<ChatSession> updatedSessions = <ChatSession>[
      ..._sessions,
      newSession,
    ];
    await widget.storageService
        .savePersonaSessions(widget.persona.id, updatedSessions);
    await widget.storageService
        .saveCurrentSessionId(widget.persona.id, newSession.sessionId);
    if (!mounted) {
      return;
    }
    setState(() {
      _sessions = updatedSessions;
      _currentSessionId = newSession.sessionId;
      _messages = <ChatMessage>[];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已新建会话')),
    );
  }

  /// 清空当前会话消息并保留会话本身。
  Future<void> _clearCurrentSession() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('确认清空会话'),
          content: const Text('清空后当前会话消息将被移除，操作不可撤销。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await _persistCurrentSessionMessages(<ChatMessage>[]);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前会话已清空')),
    );
  }

  /// 导出当前人物全部会话为 JSON 备份文件。
  Future<void> _exportSessionsBackup() async {
    /// 获取当前人物会话快照数据。
    final List<ChatSession> snapshot = _sessions;
    final Map<String, dynamic> exportData = <String, dynamic>{
      'personaId': widget.persona.id,
      'personaName': widget.persona.name,
      'exportedAt': DateTime.now().toIso8601String(),
      'sessions': snapshot.map((ChatSession session) => session.toJson()).toList(),
    };
    /// 获取应用文档目录。
    final Directory directory = await getApplicationDocumentsDirectory();
    /// 生成带时间戳的备份文件名。
    final String fileName =
        'nuwa_backup_${widget.persona.id}_${DateTime.now().millisecondsSinceEpoch}.json';
    final File file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(exportData),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导出备份: ${file.path}')),
    );
  }

  /// 读取当前会话标题用于显示在标题栏。
  String _getCurrentSessionTitle() {
    for (final ChatSession session in _sessions) {
      if (session.sessionId == _currentSessionId) {
        return session.title;
      }
    }
    return '默认会话';
  }

  /// 切换到指定会话并刷新消息列表。
  Future<void> _switchSession(String sessionId) async {
    ChatSession? targetSession;
    for (final ChatSession session in _sessions) {
      if (session.sessionId == sessionId) {
        targetSession = session;
        break;
      }
    }
    if (targetSession == null) {
      return;
    }
    /// 固化非空会话对象，避免异步后可空类型警告。
    final ChatSession selectedSession = targetSession;
    await widget.storageService
        .saveCurrentSessionId(widget.persona.id, selectedSession.sessionId);
    if (!mounted) {
      return;
    }
    setState(() {
      _currentSessionId = selectedSession.sessionId;
      _messages = selectedSession.messages;
    });
  }

  /// 展示会话选择面板，支持切换历史会话。
  Future<void> _showSessionSelector() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return SafeArea(
          child: ListView.separated(
            itemCount: _sessions.length,
            separatorBuilder: (BuildContext context, int index) =>
                const Divider(height: 0),
            itemBuilder: (BuildContext context, int index) {
              final ChatSession session = _sessions[index];
              final bool isCurrent = session.sessionId == _currentSessionId;
              return ListTile(
                title: Text(session.title),
                subtitle: Text('消息数: ${session.messages.length}'),
                trailing:
                    isCurrent ? const Icon(Icons.check_circle_outline) : null,
                onTap: () async {
                  Navigator.of(dialogContext).pop();
                  await _switchSession(session.sessionId);
                },
              );
            },
          ),
        );
      },
    );
  }

  /// 发送用户消息并等待模型回复。
  Future<void> _sendMessage() async {
    /// 获取输入文本。
    final String input = _inputController.text.trim();
    if (input.isEmpty || _isSending) {
      return;
    }
    /// 构造用户消息。
    final ChatMessage userMessage = ChatMessage(
      role: 'user',
      content: input,
      createdAt: DateTime.now().toIso8601String(),
    );
    /// 先构造“助手思考中”占位消息，提升反馈感知。
    final ChatMessage pendingAssistantMessage = ChatMessage(
      role: 'assistant',
      content: '正在思考中，请稍候...',
      createdAt: DateTime.now().toIso8601String(),
      isPending: true,
    );
    setState(() {
      _isSending = true;
      _messages = <ChatMessage>[
        ..._messages,
        userMessage,
        pendingAssistantMessage,
      ];
      _inputController.clear();
    });
    /// 先把用户消息保存到当前会话。
    await _persistCurrentSessionMessages(_messages);
    try {
      /// 使用流式输出，边生成边更新占位消息内容。
      final StringBuffer streamBuffer = StringBuffer();
      await for (final String piece in widget.llmService.streamMessage(
        config: widget.modelConfig,
        systemPrompt: widget.persona.systemPrompt,
        history: _messages,
        userInput: input,
      )) {
        streamBuffer.write(piece);
        if (!mounted) {
          return;
        }
        setState(() {
          /// 每次收到片段都刷新占位消息内容，形成“边生成边显示”。
          _messages = _messages.map((ChatMessage message) {
            if (message.isPending) {
              return ChatMessage(
                role: 'assistant',
                content: streamBuffer.toString(),
                createdAt: message.createdAt,
                isPending: true,
              );
            }
            return message;
          }).toList();
        });
      }
      final String reply = streamBuffer.toString().trim();
      if (reply.isEmpty) {
        throw Exception('模型返回内容为空');
      }
      /// 构造助手消息。
      final ChatMessage assistantMessage = ChatMessage(
        role: 'assistant',
        content: reply,
        createdAt: DateTime.now().toIso8601String(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        /// 移除占位消息并插入真实回复消息。
        final List<ChatMessage> withoutPending = _messages
            .where((ChatMessage message) => !message.isPending)
            .toList();
        _messages = <ChatMessage>[...withoutPending, assistantMessage];
      });
      await _persistCurrentSessionMessages(_messages);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $error')),
      );
      setState(() {
        /// 失败时移除占位消息，避免一直显示“思考中”。
        _messages = _messages
            .where((ChatMessage message) => !message.isPending)
            .toList();
      });
      await _persistCurrentSessionMessages(_messages);
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  /// 复制指定消息内容到系统剪贴板。
  Future<void> _copyMessage(String content) async {
    if (content.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('消息已复制到剪贴板')),
    );
  }

  /// 在桌面端展示右键菜单，提供复制消息操作。
  Future<void> _showMessageContextMenu(
    Offset globalPosition,
    String content,
  ) async {
    /// 在点击位置弹出菜单。
    final String? selectedAction = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'copy',
          child: Text('复制消息'),
        ),
      ],
    );
    if (selectedAction == 'copy') {
      await _copyMessage(content);
    }
  }

  /// 将时间格式化为 HH:mm，减少界面信息噪音。
  String _formatMessageTime(String isoTime) {
    final DateTime? parsedTime = DateTime.tryParse(isoTime);
    if (parsedTime == null) {
      return '';
    }
    final String hour = parsedTime.hour.toString().padLeft(2, '0');
    final String minute = parsedTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    /// 计算当前会话标题。
    final String currentSessionTitle = _getCurrentSessionTitle();
    return Scaffold(
      appBar: AppBar(
        title: Text('和 ${widget.persona.name} 对话（$currentSessionTitle）'),
        actions: <Widget>[
          IconButton(
            onPressed: _showSessionSelector,
            tooltip: '切换会话',
            icon: const Icon(Icons.history),
          ),
          PopupMenuButton<String>(
            onSelected: (String value) async {
              if (value == 'new') {
                await _createAndSwitchSession();
                return;
              }
              if (value == 'clear') {
                await _clearCurrentSession();
                return;
              }
              if (value == 'export') {
                await _exportSessionsBackup();
              }
            },
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'new', child: Text('新建会话')),
              PopupMenuItem<String>(value: 'clear', child: Text('清空当前会话')),
              PopupMenuItem<String>(value: 'export', child: Text('导出备份(JSON)')),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (BuildContext context, int index) {
                /// 当前渲染的消息对象。
                final ChatMessage message = _messages[index];
                /// 判断是否为用户消息。
                final bool isUser = message.role == 'user';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: GestureDetector(
                    onLongPress: () => _copyMessage(message.content),
                    onSecondaryTapDown: (TapDownDetails details) {
                      _showMessageContextMenu(
                        details.globalPosition,
                        message.content,
                      );
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment:
                          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                      children: <Widget>[
                        if (!isUser) ...<Widget>[
                          CircleAvatar(
                            radius: 14,
                            backgroundColor:
                                Theme.of(context).colorScheme.secondaryContainer,
                            child: Text(
                              widget.persona.name.isEmpty
                                  ? '人'
                                  : widget.persona.name.substring(0, 1),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 680),
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isUser
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.25)
                                    : Theme.of(context)
                                        .colorScheme
                                        .outlineVariant
                                        .withValues(alpha: 0.6),
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (message.isPending)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          message.content.isEmpty
                                              ? '正在思考中，请稍候...'
                                              : message.content,
                                        ),
                                      ),
                                    ],
                                  )
                                else if (isUser)
                                  Text(message.content)
                                else
                                  MarkdownBody(
                                    /// 完成后再渲染 Markdown，避免流式阶段的重排抖动。
                                    data: message.content,
                                    selectable: true,
                                    styleSheet: MarkdownStyleSheet.fromTheme(
                                      Theme.of(context),
                                    ).copyWith(
                                      p: Theme.of(context).textTheme.bodyMedium,
                                      h1: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                      h2: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                      horizontalRuleDecoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outlineVariant
                                                .withValues(alpha: 0.6),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      code: TextStyle(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        fontFamily: 'Consolas',
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: <Widget>[
                                    Icon(
                                      Icons.copy,
                                      size: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatMessageTime(message.createdAt),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isUser) ...<Widget>[
                          const SizedBox(width: 8),
                          const CircleAvatar(
                            radius: 14,
                            child: Icon(Icons.person, size: 16),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.8),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        child: Focus(
                          focusNode: _inputFocusNode,
                          onKeyEvent: (FocusNode node, KeyEvent event) {
                            /// 在桌面端按回车发送，Shift+回车保留换行。
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter &&
                                !HardwareKeyboard.instance.isShiftPressed) {
                              _sendMessage();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            controller: _inputController,
                            minLines: 1,
                            maxLines: 8,
                            textInputAction: TextInputAction.newline,
                            onSubmitted: (String value) {
                              /// 移动端软键盘点击发送时触发。
                              _sendMessage();
                            },
                            decoration: const InputDecoration(
                              hintText: '输入你的问题...（Enter发送，Shift+Enter换行）',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(12),
                            backgroundColor: (_isSending || _draftText.trim().isEmpty)
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.4)
                                : Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: (_isSending || _draftText.trim().isEmpty)
                              ? null
                              : _sendMessage,
                          child: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                      ),
                                )
                              : const Icon(Icons.send, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
