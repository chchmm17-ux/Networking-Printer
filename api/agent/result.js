import { createClient } from '@supabase/supabase-js';
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {auth:{persistSession:false}});
export default async function handler(req,res){
 if(req.method!=='POST')return res.status(405).json({error:'Method not allowed'});
 if(!process.env.AGENT_TOKEN||req.headers.authorization!==`Bearer ${process.env.AGENT_TOKEN}`)return res.status(401).json({error:'Unauthorized'});
 const {id,status,message}=req.body||{};
 if(!id||!['completed','failed'].includes(status))return res.status(400).json({error:'Invalid result'});
 const {data,error}=await supabase.from('print_jobs').update({status,message:String(message||'').slice(0,250),updated_at:new Date().toISOString()}).eq('id',id).eq('status','printing').select('id').maybeSingle();
 if(error)return res.status(500).json({error:'Could not update job result'});
 if(!data)return res.status(409).json({error:'Job was not in printing state'});
 return res.status(200).json({ok:true});
}