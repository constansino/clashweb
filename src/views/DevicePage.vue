<template>
  <div
    class="h-full overflow-x-hidden overflow-y-auto"
    :style="padding"
  >
    <div class="mx-3 mt-3 flex flex-col gap-2 lg:flex-row lg:items-center">
      <div class="flex min-w-0 items-center gap-2 lg:w-52 lg:shrink-0">
        <DevicePhoneMobileIcon class="text-primary h-6 w-6 shrink-0" />
        <div class="min-w-0">
          <div class="truncate text-base font-semibold">
            {{ selectedDevice?.label || $t('device') }}
          </div>
          <div class="text-base-content/55 truncate font-mono text-xs">
            {{ selectedDevice?.ip || '-' }} · {{ $t('deviceScope') }}
          </div>
        </div>
      </div>
      <div class="flex min-w-0 flex-1 flex-col gap-2 sm:flex-row">
        <input
          v-model="deviceSearch"
          class="input input-sm min-w-0 flex-1"
          :placeholder="$t('deviceSearchPlaceholder')"
          autocomplete="off"
        />
        <select
          v-model="selectedIp"
          class="select select-sm min-w-0 flex-1"
          :disabled="loading && !devices.length"
        >
          <option
            v-for="item in visibleDevices"
            :key="item.ip"
            :value="item.ip"
          >
            {{ item.label }} · {{ item.ip }}
          </option>
        </select>
      </div>
      <div class="grid grid-cols-2 gap-2 lg:flex lg:shrink-0">
        <button
          class="btn btn-sm"
          :class="loading && 'btn-disabled'"
          :title="$t('refresh')"
          @click="loadStatus"
        >
          <ArrowPathIcon
            class="h-4 w-4"
            :class="loading && 'animate-spin'"
          />
          <span>{{ $t('refresh') }}</span>
        </button>
        <button
          class="btn btn-sm"
          :title="$t('openDeviceConnections')"
          @click="
            router.push({ name: ROUTE_NAME.connections, query: { sourceIP: selectedDevice?.ip } })
          "
        >
          <ArrowTopRightOnSquareIcon class="h-4 w-4" />
          <span>{{ $t('openDeviceConnections') }}</span>
        </button>
      </div>
    </div>

    <div
      v-if="selectedDevice"
      class="border-primary/50 bg-primary/5 mx-3 mt-3 flex items-start gap-3 border-l-4 px-3 py-2.5"
    >
      <FunnelIcon class="text-primary mt-0.5 h-5 w-5 shrink-0" />
      <div class="min-w-0 text-sm">
        <div class="font-medium">
          {{ $t('deviceScope') }}：{{ selectedDevice.label }} · {{ selectedDevice.ip }}
        </div>
        <div class="text-base-content/60 mt-0.5 text-xs">{{ $t('deviceScopeDescription') }}</div>
      </div>
    </div>

    <div
      v-if="error"
      class="alert alert-error mx-3 mt-3"
    >
      <ExclamationTriangleIcon class="h-5 w-5 shrink-0" />
      <span class="break-all">{{ error }}</span>
    </div>

    <div
      v-if="loading && !selectedDevice"
      class="text-base-content/60 mx-3 mt-3 flex min-h-56 flex-col items-center justify-center gap-3 text-sm"
    >
      <span class="loading loading-spinner loading-md" />
      <span>{{ $t('loadingDeviceStatus') }}</span>
    </div>

    <template v-else-if="selectedDevice">
      <div class="grid grid-cols-2 gap-3 p-3 lg:grid-cols-4">
        <div class="base-container flex min-w-0 flex-col gap-1 p-4">
          <span class="text-base-content/60 text-xs font-semibold tracking-wider uppercase">
            {{ $t('deviceStatus') }}
          </span>
          <div class="flex items-center gap-2 text-lg font-medium">
            <span
              class="h-2.5 w-2.5 rounded-full"
              :class="
                deviceState === 'online'
                  ? 'bg-success'
                  : deviceState === 'bypassed'
                    ? 'bg-warning'
                    : 'bg-base-content/25'
              "
            />
            {{ $t(deviceState) }}
          </div>
          <span class="text-base-content/55 truncate text-xs">{{
            onlineDevice?.state || selectedDevice.mac || '-'
          }}</span>
        </div>
        <div class="base-container flex min-w-0 flex-col gap-1 p-4">
          <span class="text-base-content/60 text-xs font-semibold tracking-wider uppercase">
            {{ $t('defaultPolicy') }}
          </span>
          <span class="truncate text-lg font-medium">{{ effectivePolicy }}</span>
          <span class="text-base-content/55 truncate text-xs">{{ policyHint }}</span>
        </div>
        <div class="base-container flex min-w-0 flex-col gap-1 p-4">
          <span class="text-base-content/60 text-xs font-semibold tracking-wider uppercase">
            {{ $t('deviceOverrides') }}
          </span>
          <span class="text-lg font-medium tabular-nums">{{
            selectedRules.length + selectedPortRules.length
          }}</span>
          <span class="text-base-content/55 text-xs"
            >{{ selectedRules.length }} {{ $t('domainRules') }} · {{ selectedPortRules.length }}
            {{ $t('portRules') }}</span
          >
        </div>
        <div class="base-container flex min-w-0 flex-col gap-1 p-4">
          <span class="text-base-content/60 text-xs font-semibold tracking-wider uppercase">
            {{ $t('connections') }}
          </span>
          <span class="text-lg font-medium tabular-nums">{{ deviceConnections.length }}</span>
          <span class="text-base-content/55 truncate text-xs">{{
            selectedDevice.host || selectedDevice.ip
          }}</span>
        </div>
      </div>

      <div class="grid gap-3 px-3 pb-3 xl:grid-cols-[minmax(0,1fr)_minmax(22rem,0.8fr)]">
        <section class="base-container min-w-0 p-4">
          <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
            <div>
              <h2 class="text-base font-semibold">{{ $t('devicePolicy') }}</h2>
              <p class="text-base-content/55 mt-1 text-xs">{{ $t('devicePolicyDescription') }}</p>
            </div>
            <span
              class="badge badge-sm"
              :class="effectivePolicy === 'INHERIT' ? 'badge-ghost' : 'badge-primary'"
            >
              {{ effectivePolicy === 'INHERIT' ? $t('inheritGlobal') : $t('overrideGlobal') }}
            </span>
          </div>
          <form
            class="flex flex-col gap-2 sm:flex-row"
            @submit.prevent="savePolicy"
          >
            <input
              v-model="policyTarget"
              class="input input-sm min-w-0 flex-1"
              :class="{ 'input-error': policyTarget.trim() && !isPolicyTargetValid }"
              :placeholder="$t('policyTargetPlaceholder')"
              list="device-policy-targets"
              autocomplete="off"
            />
            <datalist id="device-policy-targets">
              <option value="INHERIT">{{ $t('inheritGlobal') }}</option>
              <option value="DIRECT">DIRECT</option>
              <option value="REJECT">REJECT</option>
              <option value="REJECT-DROP">REJECT-DROP</option>
              <option value="PASS">PASS</option>
              <option
                v-for="target in policyTargets"
                :key="target"
                :value="target"
              />
            </datalist>
            <button
              class="btn btn-primary btn-sm sm:w-24"
              :disabled="saving || !isPolicyTargetValid"
            >
              <CheckIcon class="h-4 w-4" />
              {{ $t('save') }}
            </button>
          </form>
          <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs">
            <span class="text-base-content/45">{{ $t('policyTargetTip') }}</span>
            <span
              v-if="policyTarget.trim() && !isPolicyTargetValid"
              class="text-error"
            >
              {{ $t('targetNotFound') }}
            </span>
            <span
              v-else-if="policyTarget.trim() && targetsReady"
              class="text-success"
            >
              {{ $t('targetRecognized') }}
            </span>
          </div>
          <div class="bg-base-200/50 mt-3 flex flex-wrap items-center gap-1.5 px-2.5 py-2 text-xs">
            <span class="text-base-content/55 mr-1">{{ $t('deviceRuleOrder') }}</span>
            <span class="badge badge-ghost badge-sm"
              >{{ $t('domainOverrides') }} / {{ $t('portOverrides') }}</span
            >
            <span class="text-base-content/45">→</span>
            <span class="badge badge-ghost badge-sm">{{ $t('defaultPolicy') }}</span>
            <span class="text-base-content/45">→</span>
            <span class="badge badge-ghost badge-sm">{{ $t('inheritGlobal') }}</span>
          </div>
        </section>

        <section class="base-container min-w-0 p-4">
          <div class="mb-3 flex items-center justify-between gap-2">
            <div>
              <h2 class="text-base font-semibold">{{ $t('deviceIdentity') }}</h2>
              <p class="text-base-content/55 mt-1 text-xs">{{ $t('deviceIdentityDescription') }}</p>
            </div>
            <SignalIcon class="text-base-content/45 h-5 w-5 shrink-0" />
          </div>
          <dl class="grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-2 text-sm">
            <dt class="text-base-content/55">IP</dt>
            <dd class="truncate font-mono">{{ selectedDevice.ip }}</dd>
            <dt class="text-base-content/55">MAC</dt>
            <dd class="truncate font-mono">{{ selectedDevice.mac || '-' }}</dd>
            <dt class="text-base-content/55">{{ $t('source') }}</dt>
            <dd class="truncate">{{ onlineDevice?.source || onlineDevice?.state || '-' }}</dd>
          </dl>
        </section>
      </div>

      <div class="grid gap-3 px-3 pb-3 xl:grid-cols-2">
        <section class="base-container min-w-0 p-4">
          <div class="mb-3 flex items-center justify-between gap-2">
            <div>
              <h2 class="text-base font-semibold">{{ $t('domainOverrides') }}</h2>
              <p class="text-base-content/55 mt-1 text-xs">
                {{ $t('domainOverridesDescription') }}
              </p>
            </div>
            <GlobeAltIcon class="text-base-content/45 h-5 w-5 shrink-0" />
          </div>
          <form
            class="grid gap-2 sm:grid-cols-[auto_minmax(0,1fr)_minmax(0,1fr)_auto]"
            @submit.prevent="addDomainRule"
          >
            <select
              v-model="newRuleType"
              class="select select-sm"
            >
              <option value="DOMAIN">{{ $t('exactDomain') }}</option>
              <option value="DOMAIN-SUFFIX">{{ $t('domainSuffix') }}</option>
            </select>
            <input
              v-model="newRuleMatch"
              class="input input-sm min-w-0"
              :placeholder="$t('domainPlaceholder')"
              required
            />
            <input
              v-model="newRuleTarget"
              class="input input-sm min-w-0"
              :class="{
                'input-error': newRuleTarget.trim() && !isOverrideTargetValid(newRuleTarget),
              }"
              :placeholder="$t('policyTargetPlaceholder')"
              list="device-policy-targets"
              required
            />
            <button
              class="btn btn-primary btn-sm"
              :disabled="saving || !isOverrideTargetValid(newRuleTarget)"
              :title="$t('add')"
            >
              <PlusIcon class="h-4 w-4" />
              <span class="sm:hidden">{{ $t('add') }}</span>
            </button>
          </form>
          <div class="mt-3 overflow-x-auto">
            <table class="table-sm table">
              <thead>
                <tr>
                  <th>{{ $t('match') }}</th>
                  <th>{{ $t('outbound') }}</th>
                  <th class="w-12"></th>
                </tr>
              </thead>
              <tbody>
                <tr v-if="!selectedRules.length">
                  <td
                    colspan="3"
                    class="text-base-content/50 py-5 text-center"
                  >
                    {{ $t('noDomainOverrides') }}
                  </td>
                </tr>
                <tr
                  v-for="rule in selectedRules"
                  :key="`${rule.type}:${rule.match}`"
                >
                  <td class="max-w-48 truncate">
                    <span class="text-base-content/50 mr-1 text-xs">{{
                      rule.type === 'DOMAIN' ? '=' : '⊃'
                    }}</span>
                    <span class="font-mono text-xs">{{ rule.match }}</span>
                  </td>
                  <td class="max-w-40 truncate">{{ rule.target }}</td>
                  <td>
                    <button
                      class="btn btn-ghost btn-xs text-error"
                      :title="$t('delete')"
                      :disabled="saving"
                      @click="deleteDomainRule(rule)"
                    >
                      <TrashIcon class="h-4 w-4" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="base-container min-w-0 p-4">
          <div class="mb-3 flex items-center justify-between gap-2">
            <div>
              <h2 class="text-base font-semibold">{{ $t('portOverrides') }}</h2>
              <p class="text-base-content/55 mt-1 text-xs">{{ $t('portOverridesDescription') }}</p>
            </div>
            <AdjustmentsHorizontalIcon class="text-base-content/45 h-5 w-5 shrink-0" />
          </div>
          <form
            class="grid gap-2 sm:grid-cols-[auto_minmax(0,1fr)_minmax(0,1fr)_auto]"
            @submit.prevent="addPortRule"
          >
            <select
              v-model="newPortType"
              class="select select-sm"
            >
              <option value="IN-PORT">{{ $t('inboundPort') }}</option>
              <option value="DST-PORT">{{ $t('destinationPort') }}</option>
            </select>
            <input
              v-model="newPort"
              class="input input-sm min-w-0"
              :placeholder="$t('portPlaceholder')"
              inputmode="numeric"
              required
            />
            <input
              v-model="newPortTarget"
              class="input input-sm min-w-0"
              :class="{
                'input-error': newPortTarget.trim() && !isOverrideTargetValid(newPortTarget),
              }"
              :placeholder="$t('policyTargetPlaceholder')"
              list="device-policy-targets"
              required
            />
            <button
              class="btn btn-primary btn-sm"
              :disabled="saving || !isOverrideTargetValid(newPortTarget)"
              :title="$t('add')"
            >
              <PlusIcon class="h-4 w-4" />
              <span class="sm:hidden">{{ $t('add') }}</span>
            </button>
          </form>
          <div class="mt-3 overflow-x-auto">
            <table class="table-sm table">
              <thead>
                <tr>
                  <th>{{ $t('portCondition') }}</th>
                  <th>{{ $t('outbound') }}</th>
                  <th class="w-12"></th>
                </tr>
              </thead>
              <tbody>
                <tr v-if="!selectedPortRules.length">
                  <td
                    colspan="3"
                    class="text-base-content/50 py-5 text-center"
                  >
                    {{ $t('noPortOverrides') }}
                  </td>
                </tr>
                <tr
                  v-for="rule in selectedPortRules"
                  :key="`${rule.type}:${rule.port}`"
                >
                  <td class="max-w-48 truncate">
                    <span class="text-base-content/50 mr-1 text-xs">{{
                      rule.type === 'IN-PORT' ? $t('inboundPort') : $t('destinationPort')
                    }}</span>
                    <span class="font-mono text-xs">{{ rule.port }}</span>
                  </td>
                  <td class="max-w-40 truncate">{{ rule.target }}</td>
                  <td>
                    <button
                      class="btn btn-ghost btn-xs text-error"
                      :title="$t('delete')"
                      :disabled="saving"
                      @click="deletePortRule(rule)"
                    >
                      <TrashIcon class="h-4 w-4" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <section class="base-container mx-3 mb-3 min-w-0 overflow-hidden">
        <div
          class="border-base-300/40 flex flex-wrap items-center justify-between gap-2 border-b p-4"
        >
          <div>
            <h2 class="text-base font-semibold">{{ $t('deviceConnections') }}</h2>
            <p class="text-base-content/55 mt-1 text-xs">
              {{ $t('deviceConnectionsDescription') }}
            </p>
          </div>
          <span class="badge badge-ghost">{{ deviceConnections.length }}</span>
        </div>
        <div class="overflow-x-auto">
          <table class="table-sm table">
            <thead>
              <tr>
                <th>{{ $t('host') }}</th>
                <th>{{ $t('rule') }}</th>
                <th>{{ $t('inboundPort') }}</th>
                <th>{{ $t('outbound') }}</th>
                <th>{{ $t('connectTime') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="!deviceConnections.length">
                <td
                  colspan="5"
                  class="text-base-content/50 py-8 text-center"
                >
                  {{ $t('noDeviceConnections') }}
                </td>
              </tr>
              <tr
                v-for="connection in deviceConnections"
                :key="connection.id"
              >
                <td class="max-w-56">
                  <div class="truncate font-medium">{{ getHostFromConnection(connection) }}</div>
                  <div class="text-base-content/45 truncate text-xs">
                    {{ getNetworkTypeFromConnection(connection) }}
                  </div>
                </td>
                <td class="max-w-48">
                  <div class="truncate">{{ getConnectionRule(connection) || '-' }}</div>
                  <div class="text-base-content/45 truncate text-xs">
                    {{ getConnectionRulePayload(connection) || '' }}
                  </div>
                </td>
                <td class="font-mono text-xs">{{ getInboundUserFromConnection(connection) }}</td>
                <td class="max-w-48">
                  <div class="truncate">
                    {{ getConnectionChains(connection).join(' → ') || '-' }}
                  </div>
                </td>
                <td class="text-xs whitespace-nowrap">
                  {{ formatConnectionTime(getConnectionStart(connection)) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>

    <div
      v-else-if="!loading && !error"
      class="base-container mx-3 mt-3 p-8 text-center"
    >
      <ServerIcon class="text-base-content/35 mx-auto h-8 w-8" />
      <p class="text-base-content/60 mt-2">{{ $t('noDevices') }}</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import {
  ArrowPathIcon,
  ArrowTopRightOnSquareIcon,
  AdjustmentsHorizontalIcon,
  CheckIcon,
  DevicePhoneMobileIcon,
  ExclamationTriangleIcon,
  FunnelIcon,
  GlobeAltIcon,
  PlusIcon,
  ServerIcon,
  SignalIcon,
  TrashIcon,
} from '@heroicons/vue/24/outline'
import {
  callDeviceManager,
  fetchDeviceManagerStatus,
  type DevicePortRule,
  type DeviceRule,
  type DeviceManagerStatus,
  type OnlineDevice,
} from '@/api/deviceManager'
import {
  getConnectionChains,
  getConnectionRule,
  getConnectionRulePayload,
  getConnectionSourceIP,
  getConnectionStart,
  getHostFromConnection,
  getInboundUserFromConnection,
  getNetworkTypeFromConnection,
} from '@/helper'
import { showNotification } from '@/helper/notification'
import router from '@/router'
import { activeConnections } from '@/store/connections'
import { proxyGroupList, proxyMap } from '@/assembly/proxies'
import { ROUTE_NAME } from '@/constant'
import { usePaddingForViews } from '@/composables/paddingViews'
import { activeBackend } from '@/store/setup'
import dayjs from 'dayjs'
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'

const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 0 })
const route = useRoute()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const status = ref<DeviceManagerStatus | null>(null)
const deviceSearch = ref('')
const selectedIp = ref(typeof route.query.device === 'string' ? route.query.device : '')
const policyTarget = ref('INHERIT')
const newRuleType = ref<DeviceRule['type']>('DOMAIN-SUFFIX')
const newRuleMatch = ref('')
const newRuleTarget = ref('')
const newPortType = ref<DevicePortRule['type']>('IN-PORT')
const newPort = ref('')
const newPortTarget = ref('')
let refreshTimer: number | undefined

const policyByIp = computed(
  () => new Map((status.value?.device_policies || []).map((item) => [item.ip, item])),
)
const onlineByIp = computed(
  () => new Map((status.value?.online_devices || []).map((item) => [item.ip, item])),
)
const devices = computed(() => {
  const byIp = new Map<string, { ip: string; label: string; mac: string; host: string }>()
  const add = (ip: string, label?: string, mac?: string, host?: string) => {
    if (!ip) return
    const current = byIp.get(ip)
    byIp.set(ip, {
      ip,
      label: label && label !== '-' ? label : current?.label || ip,
      mac: mac || current?.mac || '',
      host: host && host !== '-' ? host : current?.host || '',
    })
  }
  status.value?.online_devices?.forEach((item) => add(item.ip, item.host, item.mac, item.host))
  status.value?.device_policies?.forEach((item) => add(item.ip, item.label, item.mac))
  status.value?.device_rules?.forEach((item) => add(item.ip))
  status.value?.device_port_rules?.forEach((item) => add(item.ip))
  return [...byIp.values()].sort((a, b) => a.ip.localeCompare(b.ip, undefined, { numeric: true }))
})
const selectedDevice = computed(
  () => devices.value.find((item) => item.ip === selectedIp.value) || devices.value[0],
)
const visibleDevices = computed(() => {
  const query = deviceSearch.value.trim().toLowerCase()
  if (!query) return devices.value
  const matches = devices.value.filter((item) =>
    [item.ip, item.label, item.host, item.mac].some((value) => value.toLowerCase().includes(query)),
  )
  const selected = selectedDevice.value
  if (selected && !matches.some((item) => item.ip === selected.ip)) {
    return [selected, ...matches]
  }
  return matches
})
const selectedPolicy = computed(() =>
  selectedDevice.value ? policyByIp.value.get(selectedDevice.value.ip) : undefined,
)
const onlineDevice = computed<OnlineDevice | undefined>(() =>
  selectedDevice.value ? onlineByIp.value.get(selectedDevice.value.ip) : undefined,
)
const effectivePolicy = computed(() => selectedPolicy.value?.target || 'INHERIT')
const policyHint = computed(() =>
  effectivePolicy.value === 'INHERIT' ? 'MATCH · 家庭全局规则' : '设备默认出口',
)
const deviceState = computed<'online' | 'bypassed' | 'offline'>(() => {
  if (onlineDevice.value?.bypass) return 'bypassed'
  if (onlineDevice.value) return 'online'
  return 'offline'
})
const selectedRules = computed(
  () => status.value?.device_rules.filter((item) => item.ip === selectedDevice.value?.ip) || [],
)
const selectedPortRules = computed(
  () =>
    status.value?.device_port_rules.filter((item) => item.ip === selectedDevice.value?.ip) || [],
)
const deviceConnections = computed(() =>
  activeConnections.value.filter(
    (item) => getConnectionSourceIP(item) === selectedDevice.value?.ip,
  ),
)
const policyTargets = computed(() => {
  const names = new Set<string>(['DIRECT', 'REJECT', 'REJECT-DROP', 'PASS'])
  proxyGroupList.value.forEach((name) => names.add(name))
  Object.keys(proxyMap.value).forEach((name) => names.add(name))
  return [...names]
    .filter((name) => name !== 'GLOBAL')
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
})
const targetsReady = computed(() => Object.keys(proxyMap.value).length > 0)
const isKnownTarget = (value: string) => policyTargets.value.includes(value.trim())
const isPolicyTargetValid = computed(() => {
  const value = policyTarget.value.trim()
  return value === 'INHERIT' || (value !== '' && isKnownTarget(value))
})
const isOverrideTargetValid = (value: string) => {
  const target = value.trim()
  return target !== '' && target !== 'INHERIT' && isKnownTarget(target)
}

watch(
  () => devices.value,
  (items) => {
    const queryIp = typeof route.query.device === 'string' ? route.query.device : ''
    const nextIp = items.some((item) => item.ip === queryIp)
      ? queryIp
      : items.some((item) => item.ip === selectedIp.value)
        ? selectedIp.value
        : items[0]?.ip || ''
    if (nextIp && selectedIp.value !== nextIp) selectedIp.value = nextIp
  },
  { immediate: true },
)
watch(selectedIp, (ip) => {
  if (!ip) return
  const policy = policyByIp.value.get(ip)
  policyTarget.value = policy?.target || 'INHERIT'
  newRuleTarget.value = ''
  newPortTarget.value = ''
  router.replace({ query: { ...route.query, device: ip } })
})
watch(
  selectedPolicy,
  (policy) => {
    policyTarget.value = policy?.target || 'INHERIT'
  },
  { immediate: true },
)

const loadStatus = async () => {
  if (!activeBackend.value) return
  loading.value = true
  error.value = ''
  try {
    status.value = await fetchDeviceManagerStatus()
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    loading.value = false
  }
}

const mutate = async (action: string, value: string) => {
  saving.value = true
  error.value = ''
  try {
    await callDeviceManager(action, value)
    await loadStatus()
    showNotification({ content: 'deviceUpdateSuccess', type: 'alert-success' })
    return true
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : String(cause)
    return false
  } finally {
    saving.value = false
  }
}

const savePolicy = () => {
  const device = selectedDevice.value
  const target = policyTarget.value.trim()
  if (!device || !target || !isPolicyTargetValid.value) return
  mutate('set_device_policy', [device.ip, device.label, target, device.mac].join('\n'))
}

const addDomainRule = async () => {
  const device = selectedDevice.value
  if (!device || !newRuleMatch.value.trim() || !isOverrideTargetValid(newRuleTarget.value)) return
  if (
    await mutate(
      'set_device_rule',
      [device.ip, newRuleType.value, newRuleMatch.value.trim(), newRuleTarget.value.trim()].join(
        '\n',
      ),
    )
  ) {
    newRuleMatch.value = ''
    newRuleTarget.value = ''
  }
}

const deleteDomainRule = (rule: DeviceRule) => {
  mutate('del_device_rule', [rule.ip, rule.type, rule.match].join('\n'))
}

const addPortRule = async () => {
  const device = selectedDevice.value
  if (!device || !newPort.value.trim() || !isOverrideTargetValid(newPortTarget.value)) return
  if (
    await mutate(
      'set_device_port_rule',
      [device.ip, newPortType.value, newPort.value.trim(), newPortTarget.value.trim()].join('\n'),
    )
  ) {
    newPort.value = ''
    newPortTarget.value = ''
  }
}

const deletePortRule = (rule: DevicePortRule) => {
  mutate('del_device_port_rule', [rule.ip, rule.type, rule.port].join('\n'))
}

const formatConnectionTime = (start: string | number) => dayjs(start).format('HH:mm:ss')

onMounted(() => {
  loadStatus()
  refreshTimer = window.setInterval(loadStatus, 15000)
})
onUnmounted(() => {
  if (refreshTimer) window.clearInterval(refreshTimer)
})
</script>
