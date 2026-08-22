import { activeBackend } from '@/store/setup'

export type DevicePolicy = {
  ip: string
  label: string
  target: string
  mac: string
}

export type DeviceRule = {
  ip: string
  type: 'DOMAIN' | 'DOMAIN-SUFFIX'
  match: string
  target: string
}

export type DevicePortRule = {
  ip: string
  type: 'IN-PORT' | 'DST-PORT'
  port: string
  target: string
}

export type GlobalRuleOverride = {
  type: 'DOMAIN' | 'DOMAIN-SUFFIX'
  match: string
  target: string
}

export type OnlineDevice = {
  ip: string
  mac: string
  host: string
  source: string
  state: string
  bypass: boolean
}

export type DeviceManagerStatus = {
  ok: boolean
  crash_pid: string
  devices: string[]
  online_devices: OnlineDevice[]
  device_policies: DevicePolicy[]
  device_rules: DeviceRule[]
  device_port_rules: DevicePortRule[]
  global_rules: GlobalRuleOverride[]
  device_policy_log: string[]
}

const getManagerEndpoint = () => {
  const backend = activeBackend.value
  if (!backend) return ''

  const browserHost = window.location.hostname
  const host = ['127.0.0.1', 'localhost', '::1'].includes(backend.host) ? browserHost : backend.host
  return `${backend.protocol}://${host}:8399/cgi-bin/api.cgi`
}

const readJson = async (response: Response) => {
  const data = (await response.json().catch(() => ({}))) as Record<string, unknown>
  if (!response.ok || data.ok === false) {
    throw new Error(String(data.error || `设备管理服务返回 ${response.status}`))
  }
  return data
}

export const fetchDeviceManagerStatus = async () => {
  return (await callDeviceManager('status')) as unknown as DeviceManagerStatus
}

export const callDeviceManager = async (action: string, value = '') => {
  const endpoint = getManagerEndpoint()
  const backend = activeBackend.value
  if (!endpoint || !backend) throw new Error('当前没有可用的 Mihomo 后端')
  const body = new URLSearchParams({ key: backend.password || '', action, value })
  return readJson(
    await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
    }),
  )
}
