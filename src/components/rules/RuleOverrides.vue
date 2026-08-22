<template>
  <div
    class="h-[calc(100%-3rem)] overflow-x-hidden overflow-y-auto"
    :style="padding"
  >
    <div class="mx-3 mt-3 flex flex-wrap items-center justify-between gap-2">
      <div class="flex min-w-0 items-center gap-2">
        <BoltIcon class="text-primary h-6 w-6 shrink-0" />
        <div class="min-w-0">
          <h1 class="truncate text-base font-semibold">{{ $t('ruleOverrides') }}</h1>
          <div class="text-base-content/55 truncate text-xs">
            {{ $t('ruleOverridesStatus', { count: overrides.length }) }}
          </div>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <span
          v-if="status?.crash_pid"
          class="badge badge-success badge-sm gap-1"
        >
          <span class="size-1.5 rounded-full bg-current" />
          PID {{ status.crash_pid }}
        </span>
        <button
          class="btn btn-circle btn-sm"
          :title="$t('refresh')"
          :aria-label="$t('refresh')"
          :disabled="loading"
          @click="loadStatus"
        >
          <ArrowPathIcon
            class="h-4 w-4"
            :class="loading && 'animate-spin'"
          />
        </button>
      </div>
    </div>

    <div
      v-if="error"
      class="alert alert-error mx-3 mt-3"
    >
      <ExclamationTriangleIcon class="h-5 w-5 shrink-0" />
      <span class="break-all">{{ error }}</span>
    </div>

    <div class="grid gap-3 p-3 xl:grid-cols-[minmax(0,1.35fr)_minmax(22rem,0.65fr)]">
      <section class="base-container min-w-0 p-4">
        <div class="mb-3">
          <h2 class="text-base font-semibold">{{ $t('addRuleOverride') }}</h2>
          <p class="text-base-content/55 mt-1 text-xs">{{ $t('ruleOverrideDescription') }}</p>
        </div>
        <form
          class="grid gap-2 sm:grid-cols-[10rem_minmax(12rem,1fr)_minmax(12rem,1fr)_auto]"
          @submit.prevent="addOverride"
        >
          <select
            v-model="newType"
            class="select select-sm w-full"
            :aria-label="$t('type')"
          >
            <option value="DOMAIN">{{ $t('exactDomain') }}</option>
            <option value="DOMAIN-SUFFIX">{{ $t('domainSuffix') }}</option>
          </select>
          <input
            v-model="newMatch"
            class="input input-sm min-w-0"
            :placeholder="$t('ruleOverrideDomainPlaceholder')"
            autocomplete="off"
          />
          <input
            v-model="newTarget"
            class="input input-sm min-w-0"
            :class="{ 'input-error': newTarget.trim() && !isTargetValid }"
            :placeholder="$t('policyTargetPlaceholder')"
            list="global-rule-targets"
            autocomplete="off"
          />
          <datalist id="global-rule-targets">
            <option value="DIRECT" />
            <option value="REJECT" />
            <option value="REJECT-DROP" />
            <option value="PASS" />
            <option
              v-for="target in policyTargets"
              :key="target"
              :value="target"
            />
          </datalist>
          <button
            class="btn btn-primary btn-sm"
            :disabled="saving || !canSubmit"
          >
            <span
              v-if="saving"
              class="loading loading-spinner loading-sm"
            />
            <PlusIcon
              v-else
              class="h-4 w-4"
            />
            {{ $t('add') }}
          </button>
        </form>
        <div class="mt-2 flex min-h-5 flex-wrap items-center gap-x-3 gap-y-1 text-xs">
          <span class="text-base-content/45">{{ $t('ruleOverrideTargetTip') }}</span>
          <span
            v-if="newTarget.trim() && !isTargetValid"
            class="text-error"
          >
            {{ $t('targetNotFound') }}
          </span>
        </div>
      </section>

      <section class="base-container min-w-0 p-4">
        <h2 class="text-base font-semibold">{{ $t('deviceRuleOrder') }}</h2>
        <div class="mt-3 flex flex-wrap items-center gap-1.5 text-xs">
          <span class="badge badge-ghost badge-sm">{{ $t('deviceOverrides') }}</span>
          <ChevronRightIcon class="text-base-content/35 h-3.5 w-3.5" />
          <span class="badge badge-primary badge-sm">{{ $t('ruleOverrides') }}</span>
          <ChevronRightIcon class="text-base-content/35 h-3.5 w-3.5" />
          <span class="badge badge-ghost badge-sm">{{ $t('defaultPolicy') }}</span>
          <ChevronRightIcon class="text-base-content/35 h-3.5 w-3.5" />
          <span class="badge badge-ghost badge-sm">{{ $t('householdRules') }}</span>
        </div>
        <div class="text-base-content/55 mt-3 flex items-center gap-2 text-xs">
          <CheckCircleIcon class="text-success h-4 w-4 shrink-0" />
          {{ $t('ruleOverrideHotReload') }}
        </div>
      </section>
    </div>

    <section class="base-container mx-3 mb-3 min-w-0 overflow-hidden">
      <div class="border-base-content/5 flex items-center justify-between border-b px-4 py-3">
        <h2 class="text-base font-semibold">{{ $t('activeRuleOverrides') }}</h2>
        <span class="badge badge-ghost badge-sm tabular-nums">{{ overrides.length }}</span>
      </div>
      <div
        v-if="loading && !status"
        class="flex min-h-32 items-center justify-center"
      >
        <span class="loading loading-spinner loading-md" />
      </div>
      <div
        v-else-if="!overrides.length"
        class="text-base-content/45 flex min-h-32 items-center justify-center px-4 text-sm"
      >
        {{ $t('noRuleOverrides') }}
      </div>
      <div v-else>
        <div
          v-for="rule in overrides"
          :key="`${rule.type}:${rule.match}`"
          class="border-base-content/5 hover:bg-base-200/40 grid min-w-0 grid-cols-[minmax(0,1fr)_auto] items-center gap-3 border-b px-4 py-3 last:border-b-0 sm:grid-cols-[10rem_minmax(0,1fr)_minmax(10rem,0.7fr)_auto]"
        >
          <span class="badge badge-ghost badge-sm hidden sm:inline-flex">
            {{ rule.type === 'DOMAIN' ? $t('exactDomain') : $t('domainSuffix') }}
          </span>
          <div class="min-w-0">
            <div class="truncate font-mono text-sm">{{ rule.match }}</div>
            <div class="text-base-content/45 mt-0.5 text-xs sm:hidden">
              {{ rule.type === 'DOMAIN' ? $t('exactDomain') : $t('domainSuffix') }}
            </div>
          </div>
          <div class="hidden min-w-0 items-center gap-1.5 sm:flex">
            <ArrowRightIcon class="text-base-content/35 h-3.5 w-3.5 shrink-0" />
            <span class="truncate text-sm font-medium">{{ rule.target }}</span>
          </div>
          <button
            class="btn btn-circle btn-ghost btn-sm text-error"
            :title="$t('delete')"
            :aria-label="$t('delete')"
            :disabled="saving"
            @click="deleteOverride(rule)"
          >
            <span
              v-if="saving"
              class="loading loading-spinner loading-sm"
            />
            <TrashIcon
              v-else
              class="h-4 w-4"
            />
          </button>
          <div class="text-primary col-span-2 flex min-w-0 items-center gap-1.5 text-xs sm:hidden">
            <ArrowRightIcon class="h-3.5 w-3.5 shrink-0" />
            <span class="truncate">{{ rule.target }}</span>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import {
  callDeviceManager,
  fetchDeviceManagerStatus,
  type DeviceManagerStatus,
  type GlobalRuleOverride,
} from '@/api/deviceManager'
import { usePaddingForViews } from '@/composables/paddingViews'
import { showNotification } from '@/helper/notification'
import { fetchProxies, proxyGroupList, proxyMap } from '@/assembly/proxies'
import {
  ArrowPathIcon,
  ArrowRightIcon,
  BoltIcon,
  CheckCircleIcon,
  ChevronRightIcon,
  ExclamationTriangleIcon,
  PlusIcon,
  TrashIcon,
} from '@heroicons/vue/24/outline'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()
const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 8 })
const status = ref<DeviceManagerStatus | null>(null)
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const newType = ref<GlobalRuleOverride['type']>('DOMAIN')
const newMatch = ref('')
const newTarget = ref('')

const overrides = computed(() => status.value?.global_rules ?? [])
const policyTargets = computed(() => {
  const names = new Set<string>(['DIRECT', 'REJECT', 'REJECT-DROP', 'PASS'])
  proxyGroupList.value.forEach((name) => names.add(name))
  Object.keys(proxyMap.value).forEach((name) => names.add(name))
  return [...names]
    .filter((name) => name !== 'GLOBAL')
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
})
const isTargetValid = computed(() => policyTargets.value.includes(newTarget.value.trim()))
const canSubmit = computed(
  () =>
    newMatch.value.trim().length > 0 && newTarget.value.trim().length > 0 && isTargetValid.value,
)

const loadStatus = async () => {
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
    showNotification({ content: 'ruleOverrideUpdateSuccess', type: 'alert-success' })
    return true
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : String(cause)
    return false
  } finally {
    saving.value = false
  }
}

const addOverride = async () => {
  if (!canSubmit.value) return
  if (
    await mutate(
      'set_global_rule',
      [newType.value, newMatch.value.trim(), newTarget.value.trim()].join('\n'),
    )
  ) {
    newMatch.value = ''
    newTarget.value = ''
  }
}

const deleteOverride = (rule: GlobalRuleOverride) => {
  if (!window.confirm(t('deleteRuleOverrideConfirm', { domain: rule.match }))) return
  mutate('del_global_rule', [rule.type, rule.match].join('\n'))
}

onMounted(() => {
  if (!Object.keys(proxyMap.value).length) fetchProxies().catch(() => undefined)
  loadStatus()
})
</script>
