import u from "@/js/utils";

function color(id) {
    let c = u.colorForId(id);
    return "rgba("+c.r+","+c.g+","+c.b+",0.7)";
}

const radius = 25;

export class TLink {

    constructor(id, from, to) {
        this.id   = id;
        this.from = from;
        this.to   = to;
        this.selected = false;
    }

    show(ctx) {
        ctx.beginPath();
        ctx.fillStyle = 'rgb(0,0,0)';
        ctx.moveTo(this.from.x,this.from.y);
        ctx.lineTo(this.to.x,this.to.y);
        ctx.stroke();
        ctx.closePath();
    }

    linkedToNode(nodeId) {
        return this.from.id == nodeId || this.to.id == nodeId;
    }

    select() {
        this.selected = true;
    }

    unselect() {
        this.selected = false;
    }

    collide(mouseX, mouseY, timestamp) {
        const threshold = 3;
        const P = {x:mouseX, y:mouseY};
        const A = {x:this.from.x, y:this.from.y};
        const B = {x:this.to.x, y:this.to.y};
        return this.distToSegment(P, A, B) < threshold;
    }

    sqr(x) { return x*x; }
    dist2(v, w) { return this.sqr(v.x - w.x) + this.sqr(v.y - w.y); }
    distToSegmentSquared(p, v, w) {
        let l2 = this.dist2(v, w);
        if (l2 == 0) { return this.dist2(p,v); }
        let t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2;
        t = Math.max(0, Math.min(1, t));
        return this.dist2(p, {x:v.x+t*(w.x-v.x), y:v.y+t*(w.y-v.y)});
    }
    distToSegment(p, v, w) { return Math.sqrt(this.distToSegmentSquared(p, v, w)); }

}

export class TNode {

    constructor(id, x, y, links, region, hPower) {
        this.id       = id;
        this.x        = x;
        this.y        = y;
        this.links    = links;
        this.region   = region;
        this.hPower   = hPower;
        this.selected = false;
    }

    show(ctx) {
        ctx.beginPath();
        ctx.fillStyle = 'rgb(0,0,0)';
        ctx.arc(this.x, this.y, radius+2, 0, 2 * Math.PI);
        ctx.fill();
        ctx.closePath();
        ctx.beginPath();
        ctx.fillStyle = color(this.region);
        ctx.arc(this.x, this.y, radius, 0, 2 * Math.PI);
        ctx.fill();
        ctx.font = '24px serif';
        ctx.fillStyle = 'rgb(0,0,0)';
        ctx.fillText(""+this.id,this.x-5, this.y+6);
        ctx.closePath();
    }

    select() {
        this.selected = true;
    }

    unselect() {
        this.selected = false;
    }

    addLink(link) {
        this.links.push(link);
    }

    removeLink(linkId) {
        for(let i = 0; i < this.links.length; i++) {
            if(this.links[i].id == linkId) {
                this.links.splice(i,1);
                break;
            }
        }
    }

    decrementIds(removedId) {
        for(let i = 0; i < this.links.length; i++) {
            if(this.links[i] > removedId) {
                this.links[i] = this.links[i] - 1;
            }
        }
    }

    collide(mouseX, mouseY) {
        const dSq =
            (this.x - mouseX) * (this.x - mouseX) + (this.y - mouseY) * (this.y - mouseY);
        return dSq < (radius * radius);
    }

    toJSON() {
        // TODO : convert the contents of the node to JSON notation
    }

}