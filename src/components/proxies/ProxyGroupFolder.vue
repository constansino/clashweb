<template>
  <section
    class="proxy-folder-section min-w-0"
    :class="isFolderDropTarget && 'proxy-folder-over'"
    @dragover.prevent="handlerFolderDragOver"
    @dragleave="handlerFolderDragLeave"
    @drop.prevent="handlerFolderDrop"
  >
    <header class="proxy-folder-header flex min-h-10 items-center gap-2 py-1.5">
      <button
        class="proxy-layout-drag-surface no-layout-drag flex min-w-0 flex-1 items-center gap-2 text-left"
        :aria-expanded="isOpen"
        @click.stop="isOpen = !isOpen"
      >
        <ChevronRightIcon
          class="text-base-content/50 h-4 w-4 shrink-0 transition-transform"
          :class="isOpen && 'rotate-90'"
        />
        <span
          v-if="folder.emoji"
          class="text-lg leading-none"
        >
          {{ folder.emoji }}
        </span>
        <FolderOpenIcon
          v-else-if="isOpen"
          class="text-primary h-5 w-5 shrink-0"
        />
        <FolderIcon
          v-else
          class="text-primary h-5 w-5 shrink-0"
        />
        <span class="min-w-0 flex-1 truncate text-sm font-semibold">{{ folder.name }}</span>
        <span class="text-base-content/55 shrink-0 text-xs tabular-nums">
          {{ folder.children.length }}
        </span>
      </button>
      <button
        class="btn btn-circle btn-ghost btn-xs no-layout-drag shrink-0"
        :title="$t('editProxyFolder')"
        :aria-label="$t('editProxyFolder')"
        @click.stop="openEditor"
      >
        <PencilSquareIcon class="h-3.5 w-3.5" />
      </button>
    </header>

    <div
      v-if="!isOpen"
      class="text-base-content/65 flex min-h-8 items-center gap-1 overflow-hidden py-1.5"
    >
      <span
        v-for="child in previewChildren"
        :key="child.name"
        class="bg-base-200 border-base-300 max-w-36 shrink-0 truncate rounded border px-1.5 py-0.5 text-xs"
      >
        {{ child.displayName || child.name }}
      </span>
      <span
        v-if="folder.children.length === 0"
        class="text-base-content/45 text-xs"
      >
        {{ $t('dropProxyGroupHere') }}
      </span>
    </div>

    <div
      v-else
      class="proxy-folder-content pt-3"
      :class="[contentClass, isFolderDropTarget && 'proxy-folder-content-over']"
    >
      <div
        v-if="folder.children.length"
        class="grid min-w-0 gap-3"
        :style="childGridStyle"
      >
        <div
          v-for="child in folder.children"
          :key="child.name"
          class="proxy-folder-child no-layout-drag relative min-w-0"
          :class="isChildDropTarget(child.name) && 'proxy-folder-child-over'"
          :data-proxy-folder-id="folder.id"
          :data-proxy-folder-child-name="child.name"
          @pointerdown.stop="handlerChildPointerDown($event, child.name)"
          @dragover.prevent.stop="handlerChildDragOver($event, child.name)"
          @dragleave.stop="handlerChildDragLeave(child.name)"
          @drop.prevent.stop="handlerChildDrop($event, child.name)"
        >
          <button
            v-if="proxyLayoutEditing"
            class="proxy-layout-drag-handle btn btn-circle btn-sm absolute top-2 right-11 z-20"
            :title="$t('dragToReorder')"
            :aria-label="$t('dragToReorder')"
            @pointerdown.stop="handlerChildPointerDown($event, child.name)"
          >
            <Bars3Icon class="h-4 w-4" />
          </button>
          <ProxyGroup
            :name="child.name"
            :display-name="child.displayName"
          />
        </div>
      </div>
      <div
        v-else
        class="border-base-content/20 text-base-content/55 flex min-h-24 items-center justify-center rounded border border-dashed text-xs"
      >
        {{ $t('dropProxyGroupHere') }}
      </div>
    </div>
  </section>

  <DialogWrapper
    v-model="editorOpen"
    :title="$t('editProxyFolder')"
  >
    <div class="flex flex-col gap-3 text-sm">
      <div class="settings-grid">
        <div class="setting-item">
          <div class="setting-item-label">{{ $t('emoji') }}</div>
          <input
            v-model="draftEmoji"
            class="input input-sm w-20 text-center"
            maxlength="4"
          />
        </div>
        <div class="setting-item">
          <div class="setting-item-label">{{ $t('proxyFolderName') }}</div>
          <input
            v-model="draftName"
            class="input input-sm min-w-32"
          />
        </div>
        <div class="setting-item">
          <div class="setting-item-label">{{ $t('proxyFolderWidth') }}</div>
          <select
            v-model.number="draftSpan"
            class="select select-sm min-w-24"
          >
            <option
              v-for="width in widthOptions"
              :key="width"
              :value="width"
            >
              {{ width }}/{{ columnCount }}
            </option>
          </select>
        </div>
        <div class="setting-item">
          <div class="setting-item-label">{{ $t('proxyFolderHeight') }}</div>
          <select
            v-model="draftHeight"
            class="select select-sm min-w-24"
          >
            <option
              v-for="option in heightOptions"
              :key="option.value"
              :value="option.value"
            >
              {{ $t(option.labelKey) }}
            </option>
          </select>
        </div>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          class="btn btn-primary flex-1"
          @click="saveEditor"
        >
          {{ $t('save') }}
        </button>
        <button
          class="btn flex-1"
          @click="resetEditor"
        >
          {{ $t('reset') }}
        </button>
        <button
          v-if="folder.custom"
          class="btn btn-error flex-1"
          @click="deleteFolder"
        >
          {{ $t('delete') }}
        </button>
      </div>
    </div>
  </DialogWrapper>
</template>

<script setup lang="ts">
import {
  getDraggedProxyGroupName,
  getProxyLayoutDragPayload,
  moveProxyGroupInFolder,
  normalizeFolderHeight,
  normalizeFolderSpan,
  proxyLayoutEditing,
  proxyLayoutPointerDropTarget,
  PROXY_LAYOUT_POINTER_START_KEY,
  removeProxyGroupFolder,
  resetProxyGroupFolderMeta,
  setProxyGroupFolder,
  updateProxyGroupFolderMeta,
  type ProxyGroupFolderHeight,
  type ProxyGroupFolderEntry,
} from '@/composables/proxyGroupFolders'
import { collapseGroupMap } from '@/store/settings'
import {
  Bars3Icon,
  ChevronRightIcon,
  FolderIcon,
  FolderOpenIcon,
  PencilSquareIcon,
} from '@heroicons/vue/24/outline'
import { computed, inject, ref } from 'vue'
import DialogWrapper from '../common/DialogWrapper.vue'
import ProxyGroup from './ProxyGroup.vue'

const props = defineProps<{
  folder: ProxyGroupFolderEntry
  columnCount: number
}>()

const startPointerDrag = inject(PROXY_LAYOUT_POINTER_START_KEY)
const cacheName = computed(() => `folder:${props.folder.id}`)
const isOpen = computed({
  get: () => Boolean(collapseGroupMap.value[cacheName.value]),
  set: (value: boolean) => {
    collapseGroupMap.value[cacheName.value] = value
  },
})
const previewChildren = computed(() => props.folder.children.slice(0, 6))
const childNames = computed(() => props.folder.children.map((child) => child.name))
const widthOptions = computed(() =>
  Array.from({ length: props.columnCount }, (_, index) => index + 1),
)
const childGridStyle = computed(() => ({
  gridTemplateColumns: `repeat(${Math.max(1, props.columnCount)}, minmax(0, 1fr))`,
}))
const heightOptions: {
  value: ProxyGroupFolderHeight
  labelKey: 'small' | 'normal' | 'large' | 'proxyFolderHeightOpen'
}[] = [
  { value: 'compact', labelKey: 'small' },
  { value: 'normal', labelKey: 'normal' },
  { value: 'tall', labelKey: 'large' },
  { value: 'open', labelKey: 'proxyFolderHeightOpen' },
]
const contentClass = computed(() => {
  if (props.folder.height === 'normal' && props.folder.children.length <= 12) {
    return 'max-h-none overflow-visible'
  }

  const classMap: Record<ProxyGroupFolderHeight, string> = {
    compact: 'max-h-72 overflow-y-auto pr-1',
    normal: 'max-h-[70dvh] overflow-y-auto pr-1',
    tall: 'max-h-[calc(100dvh-8rem)] overflow-y-auto pr-1',
    open: 'max-h-none overflow-visible',
  }

  return classMap[props.folder.height]
})

const editorOpen = ref(false)
const draftEmoji = ref('')
const draftHeight = ref<ProxyGroupFolderHeight>('normal')
const draftName = ref('')
const draftSpan = ref(1)
const folderDragOver = ref(false)
const childDragOverName = ref('')
const isFolderDropTarget = computed(() => {
  const target = proxyLayoutPointerDropTarget.value
  return folderDragOver.value || (target?.type === 'folder' && target.folderId === props.folder.id)
})

const isChildDropTarget = (groupName: string) => {
  const target = proxyLayoutPointerDropTarget.value
  return (
    childDragOverName.value === groupName ||
    (target?.type === 'folder-child' &&
      target.folderId === props.folder.id &&
      target.groupName === groupName)
  )
}

const openEditor = () => {
  draftEmoji.value = props.folder.emoji || ''
  draftHeight.value = props.folder.height
  draftName.value = props.folder.name
  draftSpan.value = props.folder.span
  editorOpen.value = true
}

const saveEditor = () => {
  updateProxyGroupFolderMeta(props.folder.id, {
    emoji: draftEmoji.value.trim() || undefined,
    height: normalizeFolderHeight(draftHeight.value),
    name: draftName.value.trim() || props.folder.name,
    span: normalizeFolderSpan(draftSpan.value, props.columnCount),
  })
  editorOpen.value = false
}

const resetEditor = () => {
  resetProxyGroupFolderMeta(props.folder.id)
  editorOpen.value = false
}

const deleteFolder = () => {
  removeProxyGroupFolder(props.folder.id)
  editorOpen.value = false
}

const handlerFolderDragOver = (event: DragEvent) => {
  const groupName = getDraggedProxyGroupName(getProxyLayoutDragPayload(event))
  if (!groupName) return
  event.stopPropagation()
  folderDragOver.value = true
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move'
}

const handlerFolderDragLeave = () => {
  folderDragOver.value = false
}

const handlerFolderDrop = (event: DragEvent) => {
  const groupName = getDraggedProxyGroupName(getProxyLayoutDragPayload(event))
  if (groupName) {
    event.stopPropagation()
    setProxyGroupFolder(groupName, props.folder.id)
    moveProxyGroupInFolder(props.folder.id, groupName, undefined, childNames.value)
  }
  folderDragOver.value = false
  childDragOverName.value = ''
}

const handlerChildPointerDown = (event: PointerEvent, groupName: string) => {
  startPointerDrag?.(event, { type: 'group', name: groupName }, { allowNoLayoutDrag: true })
}

const handlerChildDragOver = (event: DragEvent, groupName: string) => {
  const draggedGroupName = getDraggedProxyGroupName(getProxyLayoutDragPayload(event))
  if (!draggedGroupName || draggedGroupName === groupName) return
  childDragOverName.value = groupName
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move'
}

const handlerChildDragLeave = (groupName: string) => {
  if (childDragOverName.value === groupName) childDragOverName.value = ''
}

const handlerChildDrop = (event: DragEvent, groupName: string) => {
  const draggedGroupName = getDraggedProxyGroupName(getProxyLayoutDragPayload(event))
  if (draggedGroupName) {
    setProxyGroupFolder(draggedGroupName, props.folder.id)
    moveProxyGroupInFolder(props.folder.id, draggedGroupName, groupName, childNames.value)
  }
  folderDragOver.value = false
  childDragOverName.value = ''
}
</script>

<style scoped>
.proxy-folder-section {
  border-left: 2px solid color-mix(in srgb, var(--color-primary) 32%, transparent);
  padding-left: 0.75rem;
  transition:
    border-color 0.16s ease,
    background-color 0.16s ease;
}

.proxy-folder-header {
  border-bottom: 1px solid color-mix(in srgb, var(--color-base-content) 12%, transparent);
}

.proxy-layout-drag-surface {
  cursor: grab;
  touch-action: pan-y;
}

.proxy-layout-drag-surface:active {
  cursor: grabbing;
}

.proxy-folder-over {
  border-left-color: var(--color-primary);
  background: color-mix(in srgb, var(--color-primary) 6%, transparent);
}

.proxy-folder-content-over {
  background: color-mix(in srgb, var(--color-primary) 5%, transparent);
}

.proxy-folder-child {
  cursor: grab;
  user-select: none;
  -webkit-user-drag: none;
  touch-action: pan-y;
  transition: transform 0.16s ease;
}

.proxy-folder-child :deep(*) {
  -webkit-user-drag: none;
}

.proxy-folder-child:active {
  cursor: grabbing;
}

.proxy-folder-child-over {
  box-shadow: 0 -2px 0 color-mix(in srgb, var(--color-primary) 80%, transparent);
  transform: translateY(1px);
}

.proxy-layout-drag-handle {
  cursor: grab;
  touch-action: none;
}

.proxy-layout-drag-handle:active {
  cursor: grabbing;
}
</style>
