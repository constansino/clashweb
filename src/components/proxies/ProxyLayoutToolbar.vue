<template>
  <div
    class="border-base-300/60 bg-base-100/85 flex min-h-12 flex-wrap items-center gap-2 border-b px-3 py-2 backdrop-blur-xl"
  >
    <div class="mr-auto flex min-w-0 items-center gap-2">
      <Squares2X2Icon class="text-primary h-4 w-4 shrink-0" />
      <span class="truncate text-sm font-medium">{{ $t('proxyGroupLayout') }}</span>
    </div>

    <div
      class="join shrink-0 max-sm:hidden"
      :aria-label="$t('proxyGroupColumns')"
    >
      <button
        v-for="columns in PROXY_GROUP_MAX_COLUMNS"
        :key="columns"
        class="btn btn-sm join-item min-w-9 px-2"
        :class="proxyGroupColumns === columns ? 'btn-primary' : 'btn-ghost'"
        :aria-pressed="proxyGroupColumns === columns"
        :title="`${columns} ${$t('columns')}`"
        @click="setColumns(columns)"
      >
        {{ columns }}
      </button>
    </div>

    <button
      class="btn btn-sm gap-1.5"
      :class="proxyLayoutEditing && 'btn-primary'"
      :aria-pressed="proxyLayoutEditing"
      @click="proxyLayoutEditing = !proxyLayoutEditing"
    >
      <CheckIcon
        v-if="proxyLayoutEditing"
        class="h-4 w-4"
      />
      <PencilSquareIcon
        v-else
        class="h-4 w-4"
      />
      {{ $t(proxyLayoutEditing ? 'finishLayoutEditing' : 'editLayout') }}
    </button>

    <button
      class="btn btn-sm gap-1.5"
      @click="addFolder"
    >
      <FolderPlusIcon class="h-4 w-4" />
      {{ $t('addProxyFolder') }}
    </button>

    <button
      v-if="proxyLayoutEditing"
      class="btn btn-circle btn-ghost btn-sm"
      :title="$t('reset')"
      :aria-label="$t('reset')"
      @click="resetLayout"
    >
      <ArrowUturnLeftIcon class="h-4 w-4" />
    </button>
  </div>
</template>

<script setup lang="ts">
import {
  createProxyGroupFolder,
  normalizeProxyGroupColumns,
  PROXY_GROUP_MAX_COLUMNS,
  proxyLayoutEditing,
  resetProxyGroupLayout,
} from '@/composables/proxyGroupFolders'
import { collapseGroupMap, proxyGroupColumns, twoColumnProxyGroup } from '@/store/settings'
import {
  ArrowUturnLeftIcon,
  CheckIcon,
  FolderPlusIcon,
  PencilSquareIcon,
  Squares2X2Icon,
} from '@heroicons/vue/24/outline'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

const setColumns = (value: number) => {
  proxyGroupColumns.value = normalizeProxyGroupColumns(value)
  twoColumnProxyGroup.value = proxyGroupColumns.value > 1
}

const addFolder = () => {
  const id = createProxyGroupFolder()
  collapseGroupMap.value[`folder:${id}`] = true
  proxyLayoutEditing.value = true
}

const resetLayout = () => {
  if (!confirm(t('resetProxyLayoutConfirm'))) return
  resetProxyGroupLayout()
}
</script>
