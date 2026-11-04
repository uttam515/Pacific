import {defineConfig} from '@playwright/test';
export default defineConfig({testDir:'./e2e',workers:1,retries:0,timeout:45000,use:{baseURL:'http://127.0.0.1:4000',viewport:{width:1440,height:1000},trace:'off',screenshot:'off'},reporter:'list'});
