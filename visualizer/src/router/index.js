import { createWebHistory, createRouter } from "vue-router";
import Parameters from "../views/Parameters.vue";
import Statistics from "../views/Statistics.vue";
import Visualizer from "../views/Visualizer.vue";


let routes = [
    {   
        path: "/",
        name:"landing",
        component: Parameters,
    },
    {
        path: "/parameters",
        name:"parameters",
        component: Parameters,
    },
    {
        path: "/statistics",
        name:"statistics",
        component: Statistics,
    },
    {
        path: "/visualizer",
        name:"visualizer",
        component: Visualizer,
    },
];

const router = createRouter({
    history: createWebHistory(),
    routes
  });

export default router;