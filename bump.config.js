import { defineConfig } from 'bumpp'
import tauri from 'tauri-version'

export default defineConfig({
  all: true,
  execute: tauri(),

  // execute: tauri({/* options */})

  // execute: async (ctx) => {
  //   await tauri({/* options */})(ctx)
  //   // do something
  // }
})
