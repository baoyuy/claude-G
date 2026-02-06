const express = require('express')
const fs = require('fs')
const path = require('path')
const axios = require('axios')
const claudeCodeHeadersService = require('../../services/claudeCodeHeadersService')
const claudeAccountService = require('../../services/claudeAccountService')
const redis = require('../../models/redis')
const { authenticateAdmin } = require('../../middleware/auth')
const logger = require('../../utils/logger')
const config = require('../../../config/config')

const router = express.Router()

// ==================== Claude Code Headers 管理 ====================

// 获取所有 Claude Code headers
router.get('/claude-code-headers', authenticateAdmin, async (req, res) => {
  try {
    const allHeaders = await claudeCodeHeadersService.getAllAccountHeaders()

    // 获取所有 Claude 账号信息
    const accounts = await claudeAccountService.getAllAccounts()
    const accountMap = {}
    accounts.forEach((account) => {
      accountMap[account.id] = account.name
    })

    // 格式化输出
    const formattedData = Object.entries(allHeaders).map(([accountId, data]) => ({
      accountId,
      accountName: accountMap[accountId] || 'Unknown',
      version: data.version,
      userAgent: data.headers['user-agent'],
      updatedAt: data.updatedAt,
      headers: data.headers
    }))

    return res.json({
      success: true,
      data: formattedData
    })
  } catch (error) {
    logger.error('❌ Failed to get Claude Code headers:', error)
    return res
      .status(500)
      .json({ error: 'Failed to get Claude Code headers', message: error.message })
  }
})

// 🗑️ 清除指定账号的 Claude Code headers
router.delete('/claude-code-headers/:accountId', authenticateAdmin, async (req, res) => {
  try {
    const { accountId } = req.params
    await claudeCodeHeadersService.clearAccountHeaders(accountId)

    return res.json({
      success: true,
      message: `Claude Code headers cleared for account ${accountId}`
    })
  } catch (error) {
    logger.error('❌ Failed to clear Claude Code headers:', error)
    return res
      .status(500)
      .json({ error: 'Failed to clear Claude Code headers', message: error.message })
  }
})

// ==================== 系统更新检查 ====================

const { exec } = require('child_process')
const util = require('util')
const execPromise = util.promisify(exec)

// GitHub 仓库配置
const GITHUB_REPO = 'baoyuy/claude-G'
const GITHUB_BRANCH = 'main'

// 版本比较函数
function compareVersions(current, latest) {
  const parseVersion = (v) => {
    const clean = String(v).replace(/^v/, '')
    const parts = clean.split('.').map(Number)
    return {
      major: parts[0] || 0,
      minor: parts[1] || 0,
      patch: parts[2] || 0
    }
  }

  const currentV = parseVersion(current)
  const latestV = parseVersion(latest)

  if (currentV.major !== latestV.major) {
    return currentV.major - latestV.major
  }
  if (currentV.minor !== latestV.minor) {
    return currentV.minor - latestV.minor
  }
  return currentV.patch - latestV.patch
}

// 检查是否在 Git 仓库中
async function isGitRepo(cwd) {
  try {
    await execPromise('git rev-parse --git-dir', { cwd, timeout: 5000 })
    return true
  } catch {
    return false
  }
}

// 获取本地 Git commit hash
async function getLocalCommitHash(cwd) {
  try {
    const { stdout } = await execPromise('git rev-parse HEAD', { cwd, timeout: 5000 })
    return stdout.trim()
  } catch {
    return null
  }
}

// 获取远程最新 commit hash（通过 GitHub API）
async function getRemoteCommitHash() {
  try {
    const response = await axios.get(`https://api.github.com/repos/${GITHUB_REPO}/commits/${GITHUB_BRANCH}`, {
      headers: {
        Accept: 'application/vnd.github.v3+json',
        'User-Agent': 'Claude-Relay-Service'
      },
      timeout: 15000
    })
    return {
      sha: response.data.sha,
      message: response.data.commit.message,
      date: response.data.commit.committer.date,
      author: response.data.commit.author.name
    }
  } catch (error) {
    logger.warn('⚠️ Failed to get remote commit from GitHub API:', error.message)
    return null
  }
}

// 获取远程最新 commit（通过 git fetch）
async function getRemoteCommitViaGit(cwd) {
  try {
    // 先 fetch 远程更新
    await execPromise(`git fetch origin ${GITHUB_BRANCH}`, { cwd, timeout: 30000 })
    // 获取远程分支的最新 commit
    const { stdout } = await execPromise(`git rev-parse origin/${GITHUB_BRANCH}`, { cwd, timeout: 5000 })
    return stdout.trim()
  } catch (error) {
    logger.warn('⚠️ Failed to fetch remote commit via git:', error.message)
    return null
  }
}

// 获取最近的 commits 列表（用于显示更新内容）
async function getRecentCommits(since) {
  try {
    const response = await axios.get(`https://api.github.com/repos/${GITHUB_REPO}/commits`, {
      params: {
        sha: GITHUB_BRANCH,
        since: since,
        per_page: 20
      },
      headers: {
        Accept: 'application/vnd.github.v3+json',
        'User-Agent': 'Claude-Relay-Service'
      },
      timeout: 15000
    })
    return response.data.map((c) => ({
      sha: c.sha.substring(0, 7),
      message: c.commit.message.split('\n')[0],
      date: c.commit.committer.date,
      author: c.commit.author.name
    }))
  } catch {
    return []
  }
}

router.get('/check-updates', authenticateAdmin, async (req, res) => {
  const projectRoot = path.join(__dirname, '../../..')
  const versionPath = path.join(projectRoot, 'VERSION')

  // 读取当前版本号
  let currentVersion = '1.0.0'
  try {
    currentVersion = fs.readFileSync(versionPath, 'utf8').trim()
  } catch (err) {
    logger.warn('⚠️ Could not read VERSION file:', err.message)
  }

  try {
    // 检查缓存（除非强制刷新）
    const cacheKey = 'version_check_cache_v2'
    if (!req.query.force) {
      const cached = await redis.getClient().get(cacheKey)
      if (cached) {
        const cachedData = JSON.parse(cached)
        const cacheAge = Date.now() - cachedData.timestamp
        // 缓存有效期 10 分钟
        if (cacheAge < 600000) {
          return res.json({
            success: true,
            data: {
              ...cachedData.data,
              current: currentVersion,
              cached: true
            }
          })
        }
      }
    }

    // 检查是否在 Git 仓库中
    const isGit = await isGitRepo(projectRoot)
    const isDocker = fs.existsSync('/.dockerenv')

    let localCommit = null
    let remoteCommit = null
    let hasUpdate = false
    let updateMethod = 'unknown'
    let recentCommits = []

    if (isGit && !isDocker) {
      // Git 模式：通过 git 命令检查
      updateMethod = 'git'
      localCommit = await getLocalCommitHash(projectRoot)

      // 优先使用 git fetch 获取远程 commit
      const remoteCommitHash = await getRemoteCommitViaGit(projectRoot)
      if (remoteCommitHash) {
        remoteCommit = { sha: remoteCommitHash }
      } else {
        // 回退到 GitHub API
        remoteCommit = await getRemoteCommitHash()
      }

      if (localCommit && remoteCommit) {
        hasUpdate = localCommit !== remoteCommit.sha
      }
    } else {
      // 非 Git 模式（Docker 或直接下载）：通过 GitHub API 检查
      updateMethod = isDocker ? 'docker' : 'tarball'
      remoteCommit = await getRemoteCommitHash()

      // 尝试读取本地记录的 commit hash
      const commitFilePath = path.join(projectRoot, '.git_commit')
      try {
        localCommit = fs.readFileSync(commitFilePath, 'utf8').trim()
      } catch {
        localCommit = null
      }

      if (remoteCommit) {
        hasUpdate = !localCommit || localCommit !== remoteCommit.sha
      }
    }

    // 如果有更新，获取最近的 commits
    if (hasUpdate && localCommit) {
      // 获取本地 commit 的时间
      try {
        const localCommitInfo = await axios.get(`https://api.github.com/repos/${GITHUB_REPO}/commits/${localCommit}`, {
          headers: {
            Accept: 'application/vnd.github.v3+json',
            'User-Agent': 'Claude-Relay-Service'
          },
          timeout: 10000
        })
        const sinceDate = localCommitInfo.data.commit.committer.date
        recentCommits = await getRecentCommits(sinceDate)
        // 过滤掉本地已有的 commit
        recentCommits = recentCommits.filter((c) => !localCommit.startsWith(c.sha))
      } catch {
        // 忽略错误
      }
    }

    const responseData = {
      current: currentVersion,
      latest: remoteCommit ? currentVersion : currentVersion, // 版本号保持不变，用 commit 判断
      hasUpdate,
      updateMethod,
      localCommit: localCommit ? localCommit.substring(0, 7) : null,
      remoteCommit: remoteCommit ? remoteCommit.sha.substring(0, 7) : null,
      isDocker,
      isGitRepo: isGit,
      releaseInfo: {
        name: hasUpdate ? '有新的更新可用' : '当前已是最新版本',
        body: hasUpdate
          ? recentCommits.length > 0
            ? `最近 ${recentCommits.length} 个更新:\n${recentCommits.map((c) => `• ${c.sha} ${c.message}`).join('\n')}`
            : `远程有新的提交 (${remoteCommit?.sha?.substring(0, 7)})`
          : '没有新的更新',
        publishedAt: remoteCommit?.date || new Date().toISOString(),
        htmlUrl: `https://github.com/${GITHUB_REPO}/commits/${GITHUB_BRANCH}`
      },
      recentCommits
    }

    // 缓存结果
    await redis.getClient().set(
      cacheKey,
      JSON.stringify({
        data: responseData,
        timestamp: Date.now()
      }),
      'EX',
      600
    )

    return res.json({
      success: true,
      data: responseData
    })
  } catch (error) {
    logger.error('❌ Failed to check for updates:', error.message)

    return res.json({
      success: true,
      data: {
        current: currentVersion,
        latest: currentVersion,
        hasUpdate: false,
        error: true,
        warning: error.message || 'Failed to check for updates',
        releaseInfo: {
          name: '检查更新失败',
          body: `无法检查更新: ${error.message}`,
          publishedAt: new Date().toISOString(),
          htmlUrl: `https://github.com/${GITHUB_REPO}`
        }
      }
    })
  }
})

// ==================== OEM 设置管理 ====================

// 获取OEM设置（公开接口，用于显示）
// 注意：这个端点没有 authenticateAdmin 中间件，因为前端登录页也需要访问
router.get('/oem-settings', async (req, res) => {
  try {
    const client = redis.getClient()
    const oemSettings = await client.get('oem:settings')

    // 默认设置
    const defaultSettings = {
      siteName: 'Claude Relay Service',
      siteIcon: '',
      siteIconData: '', // Base64编码的图标数据
      showAdminButton: true, // 是否显示管理后台按钮
      purchaseKeyUrl: '', // 购买密钥链接
      apiStatsNotice: {
        enabled: false,
        title: '',
        content: ''
      },
      updatedAt: new Date().toISOString()
    }

    let settings = defaultSettings
    if (oemSettings) {
      try {
        settings = { ...defaultSettings, ...JSON.parse(oemSettings) }
      } catch (err) {
        logger.warn('⚠️ Failed to parse OEM settings, using defaults:', err.message)
      }
    }

    // 添加 LDAP 启用状态到响应中
    return res.json({
      success: true,
      data: {
        ...settings,
        ldapEnabled: config.ldap && config.ldap.enabled === true
      }
    })
  } catch (error) {
    logger.error('❌ Failed to get OEM settings:', error)
    return res.status(500).json({ error: 'Failed to get OEM settings', message: error.message })
  }
})

// 更新OEM设置
router.put('/oem-settings', authenticateAdmin, async (req, res) => {
  try {
    const { siteName, siteIcon, siteIconData, showAdminButton, purchaseKeyUrl, apiStatsNotice } = req.body

    // 验证输入
    if (!siteName || typeof siteName !== 'string' || siteName.trim().length === 0) {
      return res.status(400).json({ error: 'Site name is required' })
    }

    if (siteName.length > 100) {
      return res.status(400).json({ error: 'Site name must be less than 100 characters' })
    }

    // 验证图标数据大小（如果是base64）
    if (siteIconData && siteIconData.length > 500000) {
      // 约375KB
      return res.status(400).json({ error: 'Icon file must be less than 350KB' })
    }

    // 验证图标URL（如果提供）
    if (siteIcon && !siteIconData) {
      // 简单验证URL格式
      try {
        new URL(siteIcon)
      } catch (err) {
        return res.status(400).json({ error: 'Invalid icon URL format' })
      }
    }

    const settings = {
      siteName: siteName.trim(),
      siteIcon: (siteIcon || '').trim(),
      siteIconData: (siteIconData || '').trim(), // Base64数据
      showAdminButton: showAdminButton !== false, // 默认为true
      purchaseKeyUrl: (purchaseKeyUrl || '').trim(), // 购买密钥链接
      apiStatsNotice: {
        enabled: apiStatsNotice?.enabled === true,
        title: (apiStatsNotice?.title || '').trim().slice(0, 100),
        content: (apiStatsNotice?.content || '').trim().slice(0, 2000)
      },
      updatedAt: new Date().toISOString()
    }

    const client = redis.getClient()
    await client.set('oem:settings', JSON.stringify(settings))

    logger.info(`✅ OEM settings updated: ${siteName}`)

    return res.json({
      success: true,
      message: 'OEM settings updated successfully',
      data: settings
    })
  } catch (error) {
    logger.error('❌ Failed to update OEM settings:', error)
    return res.status(500).json({ error: 'Failed to update OEM settings', message: error.message })
  }
})

// ==================== Claude Code 版本管理 ====================

router.get('/claude-code-version', authenticateAdmin, async (req, res) => {
  try {
    const CACHE_KEY = 'claude_code_user_agent:daily'

    // 获取缓存的统一User-Agent
    const unifiedUserAgent = await redis.client.get(CACHE_KEY)
    const ttl = unifiedUserAgent ? await redis.client.ttl(CACHE_KEY) : 0

    res.json({
      success: true,
      userAgent: unifiedUserAgent,
      isActive: !!unifiedUserAgent,
      ttlSeconds: ttl,
      lastUpdated: unifiedUserAgent ? new Date().toISOString() : null
    })
  } catch (error) {
    logger.error('❌ Get unified Claude Code User-Agent error:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to get User-Agent information',
      error: error.message
    })
  }
})

// 🗑️ 清除统一Claude Code User-Agent缓存
router.post('/claude-code-version/clear', authenticateAdmin, async (req, res) => {
  try {
    const CACHE_KEY = 'claude_code_user_agent:daily'

    // 删除缓存的统一User-Agent
    await redis.client.del(CACHE_KEY)

    logger.info(`🗑️ Admin manually cleared unified Claude Code User-Agent cache`)

    res.json({
      success: true,
      message: 'Unified User-Agent cache cleared successfully'
    })
  } catch (error) {
    logger.error('❌ Clear unified User-Agent cache error:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to clear cache',
      error: error.message
    })
  }
})

// ==================== 系统更新执行 ====================

// 执行系统更新（改进版：支持 stash、fetch、reset 模式）
router.post('/perform-update', authenticateAdmin, async (req, res) => {
  const projectRoot = path.join(__dirname, '../../..')

  try {
    logger.info('🔄 Starting system update...')

    // 检查是否在 Docker 环境中
    const isDocker = fs.existsSync('/.dockerenv')

    if (isDocker) {
      // Docker 环境：返回更新指令
      return res.json({
        success: true,
        isDocker: true,
        message: 'Docker 环境检测到，请在宿主机执行以下命令更新：',
        commands: ['cd /path/to/claude-G', 'docker-compose pull', 'docker-compose up -d'],
        hint: '或者使用一键更新脚本: curl -fsSL https://raw.githubusercontent.com/baoyuy/claude-G/main/scripts/update.sh | bash'
      })
    }

    // 检查是否在 Git 仓库中
    const isGit = await isGitRepo(projectRoot)
    if (!isGit) {
      return res.status(400).json({
        success: false,
        error: '当前目录不是 Git 仓库',
        message: '请使用一键部署脚本重新安装，或手动执行 git clone'
      })
    }

    const updateSteps = []

    // Step 1: 检查并 stash 本地修改
    logger.info('📋 Checking for local changes...')
    try {
      const { stdout: statusOutput } = await execPromise('git status --porcelain', {
        cwd: projectRoot,
        timeout: 10000
      })

      if (statusOutput.trim()) {
        logger.info('📦 Stashing local changes...')
        await execPromise('git stash push -m "Auto stash before update"', {
          cwd: projectRoot,
          timeout: 30000
        })
        updateSteps.push('已暂存本地修改')
      }
    } catch (stashErr) {
      logger.warn('⚠️ Stash warning:', stashErr.message)
    }

    // Step 2: Fetch 远程更新
    logger.info('📥 Fetching remote updates...')
    try {
      await execPromise(`git fetch origin ${GITHUB_BRANCH}`, {
        cwd: projectRoot,
        timeout: 60000
      })
      updateSteps.push('已获取远程更新')
    } catch (fetchErr) {
      logger.error('❌ Fetch failed:', fetchErr.message)
      return res.status(500).json({
        success: false,
        error: 'Fetch failed',
        message: `无法获取远程更新: ${fetchErr.message}`
      })
    }

    // Step 3: 获取本地和远程 commit
    const localCommit = await getLocalCommitHash(projectRoot)
    let remoteCommit = null
    try {
      const { stdout } = await execPromise(`git rev-parse origin/${GITHUB_BRANCH}`, {
        cwd: projectRoot,
        timeout: 5000
      })
      remoteCommit = stdout.trim()
    } catch {
      remoteCommit = null
    }

    if (!remoteCommit) {
      return res.status(500).json({
        success: false,
        error: '无法获取远程版本信息'
      })
    }

    // 检查是否需要更新
    if (localCommit === remoteCommit) {
      return res.json({
        success: true,
        message: '当前已是最新版本',
        updated: false,
        localCommit: localCommit.substring(0, 7),
        remoteCommit: remoteCommit.substring(0, 7)
      })
    }

    // Step 4: 执行更新（使用 reset --hard 确保完全同步）
    logger.info(`🔄 Updating from ${localCommit.substring(0, 7)} to ${remoteCommit.substring(0, 7)}...`)
    try {
      await execPromise(`git reset --hard origin/${GITHUB_BRANCH}`, {
        cwd: projectRoot,
        timeout: 60000
      })
      updateSteps.push(`已更新到 ${remoteCommit.substring(0, 7)}`)
    } catch (resetErr) {
      logger.error('❌ Reset failed:', resetErr.message)
      return res.status(500).json({
        success: false,
        error: 'Reset failed',
        message: `更新失败: ${resetErr.message}`
      })
    }

    // Step 5: 检查 package.json 是否有变化，决定是否需要 npm install
    let needsNpmInstall = false
    try {
      const { stdout: diffOutput } = await execPromise(`git diff ${localCommit}..${remoteCommit} --name-only`, {
        cwd: projectRoot,
        timeout: 10000
      })
      needsNpmInstall = diffOutput.includes('package.json') || diffOutput.includes('package-lock.json')
    } catch {
      // 保守起见，如果检查失败就执行 npm install
      needsNpmInstall = true
    }

    if (needsNpmInstall) {
      logger.info('📦 Installing dependencies...')
      try {
        await execPromise('npm install --production=false', {
          cwd: projectRoot,
          timeout: 180000
        })
        updateSteps.push('已更新依赖')
      } catch (npmErr) {
        logger.warn('⚠️ npm install warning:', npmErr.message)
        updateSteps.push('依赖更新可能不完整，建议手动执行 npm install')
      }
    }

    // Step 6: 构建前端（如果有变化）
    let needsFrontendBuild = false
    try {
      const { stdout: webDiffOutput } = await execPromise(`git diff ${localCommit}..${remoteCommit} --name-only -- web/`, {
        cwd: projectRoot,
        timeout: 10000
      })
      needsFrontendBuild = webDiffOutput.trim().length > 0
    } catch {
      needsFrontendBuild = true
    }

    if (needsFrontendBuild) {
      logger.info('🔨 Building frontend...')
      try {
        await execPromise('npm run build:web', {
          cwd: projectRoot,
          timeout: 300000
        })
        updateSteps.push('已重新构建前端')
      } catch (buildErr) {
        logger.warn('⚠️ Frontend build warning:', buildErr.message)
        updateSteps.push('前端构建可能失败，建议手动执行 npm run build:web')
      }
    }

    // 清除更新检查缓存
    try {
      await redis.getClient().del('version_check_cache_v2')
    } catch {
      // ignore
    }

    logger.info('✅ System update completed successfully')

    return res.json({
      success: true,
      message: '更新完成，请重启服务以生效',
      updated: true,
      previousCommit: localCommit.substring(0, 7),
      currentCommit: remoteCommit.substring(0, 7),
      steps: updateSteps,
      needRestart: true
    })
  } catch (error) {
    logger.error('❌ System update failed:', error)
    return res.status(500).json({
      success: false,
      error: 'Update failed',
      message: error.message
    })
  }
})

// 重启服务
router.post('/restart-service', authenticateAdmin, async (req, res) => {
  try {
    logger.info('🔄 Restarting service...')

    // 发送响应后再重启
    res.json({
      success: true,
      message: '服务即将重启...'
    })

    // 延迟1秒后重启，确保响应已发送
    setTimeout(() => {
      logger.info('👋 Service restarting now...')
      process.exit(0) // PM2或Docker会自动重启
    }, 1000)

  } catch (error) {
    logger.error('❌ Service restart failed:', error)
    return res.status(500).json({
      success: false,
      error: 'Restart failed',
      message: error.message
    })
  }
})

// 获取系统信息
router.get('/system-info', authenticateAdmin, async (req, res) => {
  try {
    const versionPath = path.join(__dirname, '../../../VERSION')
    let currentVersion = '1.0.0'
    try {
      currentVersion = fs.readFileSync(versionPath, 'utf8').trim()
    } catch (err) {
      // ignore
    }

    const isDocker = fs.existsSync('/.dockerenv')
    const uptime = process.uptime()
    const memUsage = process.memoryUsage()

    return res.json({
      success: true,
      data: {
        version: currentVersion,
        isDocker,
        nodeVersion: process.version,
        platform: process.platform,
        uptime: Math.floor(uptime),
        memory: {
          used: Math.round(memUsage.heapUsed / 1024 / 1024),
          total: Math.round(memUsage.heapTotal / 1024 / 1024)
        },
        pid: process.pid
      }
    })
  } catch (error) {
    logger.error('❌ Failed to get system info:', error)
    return res.status(500).json({
      success: false,
      error: error.message
    })
  }
})

module.exports = router
