import { createReadStream, existsSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'
import { WebSocket, WebSocketServer } from 'ws'

const HOST = '127.0.0.1'
const STATIC_PORT = 4173
const MIHOMO_PORT = 19090
const MANAGER_PORT = 8399
const SECRET = 'demo-secret'
const DIST = fileURLToPath(new URL('../dist', import.meta.url))

const history = (delay) => [{ time: new Date().toISOString(), delay }]
const leaf = (name, type, delay, extra = {}) => ({
  name,
  type,
  history: history(delay),
  extra: {},
  now: name,
  icon: '',
  udp: true,
  ...extra,
})
const group = (name, all, now) => ({
  name,
  type: 'Selector',
  history: [],
  extra: {},
  all,
  now,
  icon: '',
  udp: true,
})

const proxies = {
  DIRECT: leaf('DIRECT', 'Direct', 1),
  REJECT: leaf('REJECT', 'Reject', 0),
  'TW Edge A': leaf('TW Edge A', 'ss', 42, { 'provider-name': 'Demo Transit' }),
  'TW Edge B': leaf('TW Edge B', 'ss', 58, { 'provider-name': 'Demo Transit' }),
  'US Edge A': leaf('US Edge A', 'vless', 96, { 'provider-name': 'Demo Backup' }),
  'US Edge B': leaf('US Edge B', 'vless', 112, { 'provider-name': 'Demo Backup' }),
  'Global Select': group(
    'Global Select',
    ['TW Edge A', 'TW Edge B', 'US Edge A', 'US Edge B', 'DIRECT'],
    'TW Edge A',
  ),
  Streaming: group('Streaming', ['Global Select', 'TW Edge A', 'US Edge A', 'DIRECT'], 'TW Edge A'),
  'Port 42001': group('Port 42001', ['Global Select', 'US Edge A', 'US Edge B'], 'US Edge B'),
  GLOBAL: group('GLOBAL', ['Global Select', 'Streaming', 'Port 42001'], 'Global Select'),
}

const rules = [
  {
    type: 'Domain',
    payload: 'stream.example.com',
    proxy: 'Streaming',
    size: 0,
    uuid: 'r1',
    index: 0,
  },
  {
    type: 'DomainSuffix',
    payload: 'example.net',
    proxy: 'Global Select',
    size: 0,
    uuid: 'r2',
    index: 1,
  },
  { type: 'InPort', payload: '42001', proxy: 'Port 42001', size: 0, uuid: 'r3', index: 2 },
  { type: 'IPCIDR', payload: '192.168.0.0/16', proxy: 'DIRECT', size: 0, uuid: 'r4', index: 3 },
  { type: 'Match', payload: '', proxy: 'Global Select', size: 0, uuid: 'r5', index: 4 },
]

const providers = {
  'Demo Transit': {
    name: 'Demo Transit',
    vehicleType: 'HTTP',
    testUrl: 'https://www.gstatic.com/generate_204',
    updatedAt: new Date(Date.now() - 15 * 60 * 1000).toISOString(),
    subscriptionInfo: { Download: 8e9, Upload: 2e9, Total: 100e9, Expire: 1924905600 },
    proxies: [proxies['TW Edge A'], proxies['TW Edge B']],
  },
  'Demo Backup': {
    name: 'Demo Backup',
    vehicleType: 'HTTP',
    testUrl: 'https://www.gstatic.com/generate_204',
    updatedAt: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
    proxies: [proxies['US Edge A'], proxies['US Edge B']],
  },
}

const managerState = {
  device_policies: [
    { ip: '192.168.1.20', label: 'Demo Phone', target: 'INHERIT', mac: '02:00:00:00:00:20' },
    { ip: '192.168.1.30', label: 'Living Room TV', target: 'Streaming', mac: '02:00:00:00:00:30' },
  ],
  device_rules: [
    { ip: '192.168.1.20', type: 'DOMAIN', match: 'stream.example.com', target: 'TW Edge A' },
  ],
  device_port_rules: [{ ip: '192.168.1.20', type: 'IN-PORT', port: '42001', target: 'US Edge B' }],
  global_rules: [{ type: 'DOMAIN-SUFFIX', match: 'news.example.net', target: 'Global Select' }],
}

let dashboardSettings = {
  'config/proxy-folder-mode-setting': JSON.stringify('on'),
  'config/proxy-group-columns': JSON.stringify(2),
  'config/proxy-group-folder-meta-map': JSON.stringify({
    'demo-everyday': {
      custom: true,
      height: 'open',
      name: 'Everyday',
      span: 2,
    },
  }),
  'config/proxy-group-folder-assignments': JSON.stringify({
    'Global Select': 'demo-everyday',
    Streaming: 'demo-everyday',
  }),
  'config/proxy-group-entry-order': JSON.stringify(['folder:demo-everyday']),
  'config/proxy-group-folder-child-order': JSON.stringify({
    'demo-everyday': ['Global Select', 'Streaming'],
  }),
}

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
  'Access-Control-Allow-Methods': 'GET, PUT, PATCH, POST, DELETE, OPTIONS',
  'Cache-Control': 'no-store',
}

const json = (res, value, status = 200) => {
  res.writeHead(status, { ...cors, 'Content-Type': 'application/json; charset=utf-8' })
  res.end(JSON.stringify(value))
}

const collectBody = async (req) => {
  let body = ''
  for await (const chunk of req) body += chunk
  return body
}

const demoConnections = () => ({
  downloadTotal: 4_280_000_000,
  uploadTotal: 860_000_000,
  memory: 128_000_000,
  connections: [
    {
      id: 'demo-connection-1',
      download: 24_800_000,
      upload: 1_200_000,
      chains: ['TW Edge A', 'Streaming'],
      rule: 'Domain',
      rulePayload: 'stream.example.com',
      start: new Date(Date.now() - 42_000).toISOString(),
      metadata: {
        destinationGeoIP: 'TW',
        destinationIP: '203.0.113.20',
        destinationIPASN: 'AS64500',
        destinationPort: '443',
        dnsMode: 'fake-ip',
        dscp: 0,
        host: 'stream.example.com',
        inboundIP: '0.0.0.0',
        inboundName: 'mixed-in',
        inboundPort: '7890',
        inboundUser: '',
        network: 'tcp',
        process: 'DemoPlayer',
        processPath: '',
        remoteDestination: '203.0.113.20:443',
        sniffHost: 'stream.example.com',
        sourceGeoIP: '',
        sourceIP: '192.168.1.20',
        sourceIPASN: '',
        sourcePort: '53120',
        specialProxy: '',
        specialRules: '',
        type: 'TUN',
        uid: 0,
        smartBlock: '',
      },
    },
  ],
})

const mihomoServer = createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return json(res, {})
  if (req.headers.authorization !== `Bearer ${SECRET}`)
    return json(res, { message: 'Unauthorized' }, 401)

  const url = new URL(req.url ?? '/', `http://${HOST}:${MIHOMO_PORT}`)
  const path = url.pathname
  if (path === '/version') return json(res, { version: 'Mihomo Meta v1.19.24 demo' })
  if (path === '/storage/zashboard') {
    if (req.method === 'PUT') {
      dashboardSettings = JSON.parse((await collectBody(req)) || '{}')
    } else if (req.method === 'DELETE') {
      dashboardSettings = {}
    }
    return json(res, dashboardSettings)
  }
  if (path === '/configs') {
    return json(res, {
      port: 7890,
      'socks-port': 7891,
      'mixed-port': 7890,
      'redir-port': 7892,
      'tproxy-port': 7893,
      'allow-lan': true,
      'bind-address': '*',
      mode: 'rule',
      'mode-list': ['rule', 'global', 'direct'],
      modes: ['rule', 'global', 'direct'],
      'log-level': 'info',
      ipv6: true,
      tun: { enable: true },
    })
  }
  if (path === '/proxies') return json(res, { proxies })
  if (path === '/providers/proxies') {
    await new Promise((resolve) => setTimeout(resolve, 650))
    return json(res, { providers })
  }
  if (path === '/rules') return json(res, { rules })
  if (path === '/providers/rules') {
    return json(res, {
      providers: {
        'Demo Rules': {
          name: 'Demo Rules',
          behavior: 'domain',
          format: 'yaml',
          ruleCount: 12,
          type: 'HTTP',
          vehicleType: 'HTTP',
          updatedAt: new Date().toISOString(),
        },
      },
    })
  }
  if (path === '/connections' && req.method === 'DELETE') return json(res, {})
  if (path.startsWith('/connections/') && req.method === 'DELETE') return json(res, {})
  if (path.startsWith('/group/') && path.endsWith('/delay')) {
    return json(res, { 'TW Edge A': 42, 'TW Edge B': 58, 'US Edge A': 96, 'US Edge B': 112 })
  }
  if (path.startsWith('/proxies/') && path.endsWith('/delay')) return json(res, { delay: 48 })
  if (path.startsWith('/providers/proxies/') && path.endsWith('/healthcheck')) return json(res, {})
  if (path.startsWith('/providers/proxies/') && req.method === 'PUT') return json(res, {})
  if (path.startsWith('/providers/rules/') && req.method === 'PUT') return json(res, {})
  if (path.startsWith('/proxies/')) {
    const name = decodeURIComponent(path.slice('/proxies/'.length))
    const proxy = proxies[name]
    if (!proxy) return json(res, { message: 'Proxy not found' }, 404)
    if (req.method === 'PUT') {
      const body = JSON.parse((await collectBody(req)) || '{}')
      if (proxy.all?.includes(body.name)) proxy.now = body.name
      return json(res, {})
    }
    return json(res, proxy)
  }
  if (req.method === 'PATCH' || req.method === 'POST' || req.method === 'DELETE')
    return json(res, {})
  return json(res, { message: `Unhandled demo endpoint: ${path}` }, 404)
})

const wsServer = new WebSocketServer({ noServer: true })
mihomoServer.on('upgrade', (request, socket, head) => {
  const url = new URL(request.url ?? '/', `http://${HOST}:${MIHOMO_PORT}`)
  if (url.searchParams.get('token') !== SECRET) return socket.destroy()
  wsServer.handleUpgrade(request, socket, head, (ws) => {
    const send = () => {
      if (ws.readyState !== WebSocket.OPEN) return
      if (url.pathname === '/connections') ws.send(JSON.stringify(demoConnections()))
      else if (url.pathname === '/traffic') ws.send(JSON.stringify({ up: 24_000, down: 280_000 }))
      else if (url.pathname === '/memory')
        ws.send(JSON.stringify({ inuse: 128_000_000, oslimit: 0 }))
      else if (url.pathname === '/logs')
        ws.send(JSON.stringify({ type: 'info', payload: 'demo connection ready' }))
    }
    send()
    const timer = setInterval(send, 1000)
    ws.on('close', () => clearInterval(timer))
  })
})

const managerStatus = () => ({
  ok: true,
  crash_pid: '4242',
  devices: managerState.device_policies.map((item) => item.ip),
  online_devices: [
    {
      ip: '192.168.1.20',
      mac: '02:00:00:00:00:20',
      host: 'Demo Phone',
      source: 'demo',
      state: 'REACHABLE',
      bypass: false,
    },
    {
      ip: '192.168.1.30',
      mac: '02:00:00:00:00:30',
      host: 'Living Room TV',
      source: 'demo',
      state: 'REACHABLE',
      bypass: false,
    },
  ],
  ...managerState,
  device_policy_log: ['demo manager: configuration validated', 'demo manager: hot reload complete'],
})

const managerServer = createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return json(res, {})
  const params = new URLSearchParams(await collectBody(req))
  if (params.get('key') !== SECRET) return json(res, { ok: false, error: 'bad key' }, 403)
  const action = params.get('action') ?? 'status'
  const lines = (params.get('value') ?? '').split('\n')

  if (action === 'set_device_policy') {
    managerState.device_policies = managerState.device_policies.filter(
      (item) => item.ip !== lines[0],
    )
    managerState.device_policies.push({
      ip: lines[0],
      label: lines[1],
      target: lines[2],
      mac: lines[3],
    })
  } else if (action === 'set_device_rule') {
    managerState.device_rules = managerState.device_rules.filter(
      (item) => !(item.ip === lines[0] && item.type === lines[1] && item.match === lines[2]),
    )
    managerState.device_rules.push({
      ip: lines[0],
      type: lines[1],
      match: lines[2],
      target: lines[3],
    })
  } else if (action === 'del_device_rule') {
    managerState.device_rules = managerState.device_rules.filter(
      (item) => !(item.ip === lines[0] && item.type === lines[1] && item.match === lines[2]),
    )
  } else if (action === 'set_device_port_rule') {
    managerState.device_port_rules = managerState.device_port_rules.filter(
      (item) => !(item.ip === lines[0] && item.type === lines[1] && item.port === lines[2]),
    )
    managerState.device_port_rules.push({
      ip: lines[0],
      type: lines[1],
      port: lines[2],
      target: lines[3],
    })
  } else if (action === 'del_device_port_rule') {
    managerState.device_port_rules = managerState.device_port_rules.filter(
      (item) => !(item.ip === lines[0] && item.type === lines[1] && item.port === lines[2]),
    )
  } else if (action === 'set_global_rule') {
    managerState.global_rules = managerState.global_rules.filter(
      (item) => !(item.type === lines[0] && item.match === lines[1]),
    )
    managerState.global_rules.push({ type: lines[0], match: lines[1], target: lines[2] })
  } else if (action === 'del_global_rule') {
    managerState.global_rules = managerState.global_rules.filter(
      (item) => !(item.type === lines[0] && item.match === lines[1]),
    )
  }
  return json(res, managerStatus())
})

const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.webp': 'image/webp',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
}

const staticServer = createServer((req, res) => {
  const url = new URL(req.url ?? '/', `http://${HOST}:${STATIC_PORT}`)
  const relative = normalize(decodeURIComponent(url.pathname)).replace(/^(\.\.[/\\])+/, '')
  let file = join(DIST, relative === '/' ? 'index.html' : relative)
  if (!file.startsWith(DIST) || !existsSync(file) || statSync(file).isDirectory())
    file = join(DIST, 'index.html')
  res.writeHead(200, { 'Content-Type': contentTypes[extname(file)] ?? 'application/octet-stream' })
  createReadStream(file).pipe(res)
})

staticServer.listen(STATIC_PORT, HOST)
mihomoServer.listen(MIHOMO_PORT, HOST)
managerServer.listen(MANAGER_PORT, HOST)

console.log(
  `clashweb demo: http://${HOST}:${STATIC_PORT}/?hostname=${HOST}&port=${MIHOMO_PORT}&secret=${SECRET}&label=Demo#/devices?device=192.168.1.20`,
)

const shutdown = () => {
  for (const client of wsServer.clients) client.terminate()
  wsServer.close()
  staticServer.close()
  mihomoServer.close()
  managerServer.close()
}
process.on('SIGINT', shutdown)
process.on('SIGTERM', shutdown)
